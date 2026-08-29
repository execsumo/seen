#!/bin/bash
set -euo pipefail

# Build SeenApp, install it to /Applications
# Usage: ./scripts/bundle.sh [--release] [--sign IDENTITY] [--output DIR]

BUNDLE_ID="com.execsumo.seen"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="debug"
SIGN_IDENTITY=""
OUTPUT_DIR="$REPO_ROOT/build"
NO_INSTALL=0

# Default tracks the newest tag so a local build never stamps a stale version.
# The release workflow always passes --version explicitly.
APP_VERSION="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
APP_VERSION="${APP_VERSION:-0.0.0-dev}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)    BUILD_CONFIG="release"; shift ;;
        --sign)       SIGN_IDENTITY="$2"; shift 2 ;;
        --output)     OUTPUT_DIR="$2"; shift 2 ;;
        --version)    APP_VERSION="$2"; shift 2 ;;
        --no-install) NO_INSTALL=1; shift ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

APP_NAME="Seen"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
INSTALLED="/Applications/$APP_NAME.app"

# The `seen` CLI is built and embedded alongside the app, not just the app
# itself: `seen mcp` is the MCP transport, so an install without the CLI cannot
# serve agents at all. The cask's `binary` stanza symlinks it onto PATH.
# Two invocations, not `--product A --product B`: SwiftPM's --product is
# last-wins, so passing it twice silently builds only the second product.
echo "==> Building $APP_NAME ($BUILD_CONFIG)..."
if [[ "$BUILD_CONFIG" == "release" ]]; then
    swift build -c release --product SeenApp --package-path "$REPO_ROOT"
    swift build -c release --product seen    --package-path "$REPO_ROOT"
    BUILD_BIN_DIR="$REPO_ROOT/.build/release"
else
    swift build --product SeenApp --package-path "$REPO_ROOT"
    swift build --product seen    --package-path "$REPO_ROOT"
    BUILD_BIN_DIR="$REPO_ROOT/.build/debug"
fi
BINARY="$BUILD_BIN_DIR/SeenApp"
CLI_BINARY="$BUILD_BIN_DIR/seen"

if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

if [[ ! -f "$CLI_BINARY" ]]; then
    echo "ERROR: CLI binary not found at $CLI_BINARY"
    exit 1
fi

echo "==> Creating app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# The CLI goes in Resources/bin, NOT Contents/MacOS. macOS filesystems are
# case-insensitive, so Contents/MacOS/seen IS Contents/MacOS/Seen — copying the
# CLI there silently overwrites the app's own executable and produces a bundle
# that cannot launch. That shipped as v0.1.1; hence the guard below.
mkdir -p "$APP_BUNDLE/Contents/Resources/bin"
cp "$CLI_BINARY" "$APP_BUNDLE/Contents/Resources/bin/seen"

# Fail loudly if either payload isn't byte-identical to what we just built.
if ! cmp -s "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"; then
    echo "ERROR: $APP_BUNDLE/Contents/MacOS/$APP_NAME is not the SeenApp binary."
    exit 1
fi
if ! cmp -s "$CLI_BINARY" "$APP_BUNDLE/Contents/Resources/bin/seen"; then
    echo "ERROR: $APP_BUNDLE/Contents/Resources/bin/seen is not the seen CLI binary."
    exit 1
fi

# JetBrains Mono ships inside the bundle: DESIGN.md's typography is that family
# exclusively, and the app registers these faces at launch from
# Contents/Resources/Fonts. Without them a Mac that has never installed the
# family silently falls back to the system monospace face.
FONT_SRC="$REPO_ROOT/Sources/SeenApp/Resources/Fonts"
mkdir -p "$APP_BUNDLE/Contents/Resources/Fonts"
cp "$FONT_SRC"/*.ttf "$APP_BUNDLE/Contents/Resources/Fonts/"
cp "$FONT_SRC/OFL.txt" "$APP_BUNDLE/Contents/Resources/Fonts/OFL.txt"

for face in Regular Medium SemiBold Bold; do
    if ! cmp -s "$FONT_SRC/JetBrainsMono-$face.ttf" \
                "$APP_BUNDLE/Contents/Resources/Fonts/JetBrainsMono-$face.ttf"; then
        echo "ERROR: JetBrainsMono-$face.ttf did not copy into the bundle."
        exit 1
    fi
done

mkdir -p "$APP_BUNDLE/Contents/Resources/seen-skill"
cp "$REPO_ROOT/.claude/skills/seen/SKILL.md" "$APP_BUNDLE/Contents/Resources/seen-skill/SKILL.md"

if ! cmp -s "$REPO_ROOT/.claude/skills/seen/SKILL.md" "$APP_BUNDLE/Contents/Resources/seen-skill/SKILL.md"; then
    echo "ERROR: $APP_BUNDLE/Contents/Resources/seen-skill/SKILL.md is not the correct skill file."
    exit 1
fi


# Create Info.plist dynamically with LSUIElement true
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Create Entitlements dynamically (need Screen Recording for Seen, no audio needed for now but let's just make a basic one)
cat > "$APP_BUNDLE/Contents/Resources/Seen.entitlements" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
</dict>
</plist>
EOF

if [[ -z "$SIGN_IDENTITY" ]]; then
    # `security find-identity` prints the team ID inside the quotes (e.g.
    # `"Developer ID Application: Herwin Gill (577WHA43TF)"`), so match on the
    # prefix and extract the full quoted name instead of hardcoding it — a
    # hardcoded exact match never fires because the closing quote never lands
    # right after "Herwin Gill".
    DETECTED_IDENTITY="$(security find-identity -v -p codesigning \
        | grep -o '"Developer ID Application: Herwin Gill[^"]*"' \
        | head -1 | tr -d '"')"
    if [[ -n "$DETECTED_IDENTITY" ]]; then
        SIGN_IDENTITY="$DETECTED_IDENTITY"
    elif security find-identity -v -p codesigning | grep -q '"Dev Cert"'; then
        SIGN_IDENTITY="Dev Cert"
    fi
fi

# Signing is inside-out: the nested `seen` executable must be signed before the
# bundle that contains it, or the outer signature seals an unsigned binary and
# notarization rejects the whole app.
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Signing with identity: $SIGN_IDENTITY"
    CODESIGN_EXTRA_FLAGS=""
    if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
        CODESIGN_EXTRA_FLAGS="--options runtime --timestamp"
    fi
    codesign --force \
        $CODESIGN_EXTRA_FLAGS \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE/Contents/Resources/bin/seen"
    codesign --force \
        $CODESIGN_EXTRA_FLAGS \
        --entitlements "$APP_BUNDLE/Contents/Resources/Seen.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"
else
    echo "==> Ad-hoc signing..."
    codesign --force --sign - "$APP_BUNDLE/Contents/Resources/bin/seen"
    codesign --force --sign - \
        --entitlements "$APP_BUNDLE/Contents/Resources/Seen.entitlements" \
        "$APP_BUNDLE"
fi

if [[ "$NO_INSTALL" -eq 1 ]]; then
    echo "==> Skipping install (--no-install). Bundle at $APP_BUNDLE"
else
    echo "==> Installing to $INSTALLED..."
    rm -rf "$INSTALLED"
    cp -R "$APP_BUNDLE" "$INSTALLED"
fi

echo "==> Done."
