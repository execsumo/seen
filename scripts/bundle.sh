#!/bin/bash
set -euo pipefail

# Build SeenApp, install it to /Applications
# Usage: ./scripts/bundle.sh [--release] [--sign IDENTITY] [--output DIR]

BUNDLE_ID="com.execsumo.seen"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_CONFIG="debug"
SIGN_IDENTITY=""
OUTPUT_DIR="$REPO_ROOT/build"

APP_VERSION="0.1.0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --release)    BUILD_CONFIG="release"; shift ;;
        --sign)       SIGN_IDENTITY="$2"; shift 2 ;;
        --output)     OUTPUT_DIR="$2"; shift 2 ;;
        --version)    APP_VERSION="$2"; shift 2 ;;
        *)            echo "Unknown option: $1"; exit 1 ;;
    esac
done

APP_NAME="Seen"
APP_BUNDLE="$OUTPUT_DIR/$APP_NAME.app"
INSTALLED="/Applications/$APP_NAME.app"

echo "==> Building $APP_NAME ($BUILD_CONFIG)..."
if [[ "$BUILD_CONFIG" == "release" ]]; then
    swift build -c release --product SeenApp --package-path "$REPO_ROOT"
    BINARY="$REPO_ROOT/.build/release/SeenApp"
else
    swift build --product SeenApp --package-path "$REPO_ROOT"
    BINARY="$REPO_ROOT/.build/debug/SeenApp"
fi

if [[ ! -f "$BINARY" ]]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

echo "==> Creating app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

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
    if security find-identity -v -p codesigning | grep -q '"Developer ID Application: Herwin Gill"'; then
        SIGN_IDENTITY="Developer ID Application: Herwin Gill (577WHA43TF)"
    elif security find-identity -v -p codesigning | grep -q '"Dev Cert"'; then
        SIGN_IDENTITY="Dev Cert"
    fi
fi

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> Signing with identity: $SIGN_IDENTITY"
    CODESIGN_EXTRA_FLAGS=""
    if [[ "$SIGN_IDENTITY" == Developer\ ID\ Application:* ]]; then
        CODESIGN_EXTRA_FLAGS="--options runtime --timestamp"
    fi
    codesign --force \
        $CODESIGN_EXTRA_FLAGS \
        --entitlements "$APP_BUNDLE/Contents/Resources/Seen.entitlements" \
        --sign "$SIGN_IDENTITY" \
        "$APP_BUNDLE"
else
    echo "==> Ad-hoc signing..."
    codesign --force --sign - \
        --entitlements "$APP_BUNDLE/Contents/Resources/Seen.entitlements" \
        "$APP_BUNDLE"
fi

echo "==> Installing to $INSTALLED..."
rm -rf "$INSTALLED"
cp -R "$APP_BUNDLE" "$INSTALLED"

echo "==> Done."
