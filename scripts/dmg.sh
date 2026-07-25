#!/bin/bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGN_IDENTITY=""
NOTARY_PROFILE="heard-notary"
API_KEY_PATH=""
API_KEY_ID=""
API_ISSUER_ID=""
OUTPUT_DIR="$REPO_ROOT/dist"
SKIP_NOTARIZE=0
# Default tracks the newest tag; the release workflow passes --version.
VERSION="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
VERSION="${VERSION:-0.0.0-dev}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sign)           SIGN_IDENTITY="$2"; shift 2 ;;
        --notary-profile) NOTARY_PROFILE="$2"; shift 2 ;;
        --api-key-path)   API_KEY_PATH="$2"; shift 2 ;;
        --api-key-id)     API_KEY_ID="$2"; shift 2 ;;
        --api-issuer-id)  API_ISSUER_ID="$2"; shift 2 ;;
        --output)         OUTPUT_DIR="$2"; shift 2 ;;
        --version)        VERSION="$2"; shift 2 ;;
        --skip-notarize)  SKIP_NOTARIZE=1; shift ;;
        *)                echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -n "$API_KEY_PATH" ]]; then
    NOTARY_AUTH=(--key "$API_KEY_PATH" --key-id "$API_KEY_ID" --issuer "$API_ISSUER_ID")
else
    NOTARY_AUTH=(--keychain-profile "$NOTARY_PROFILE")
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "ERROR: --sign is required."
    exit 1
fi

APP_NAME="Seen"
BUILD_DIR="$REPO_ROOT/build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

mkdir -p "$OUTPUT_DIR"

echo "==> Building release app bundle..."
"$REPO_ROOT/scripts/bundle.sh" --release --sign "$SIGN_IDENTITY" --output "$BUILD_DIR" --version "$VERSION"

echo ""
echo "==> Verifying hardened runtime..."
codesign --display --verbose=4 "$APP_BUNDLE" 2>&1 | grep -E "(flags|runtime|Authority)" || true
codesign --verify --deep --strict "$APP_BUNDLE"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    APP_ZIP="$OUTPUT_DIR/${APP_NAME}-${VERSION}.app.zip"
    echo ""
    echo "==> Zipping $APP_NAME.app for notarization submission..."
    ditto -c -k --keepParent "$APP_BUNDLE" "$APP_ZIP"

    echo "==> Notarizing $APP_NAME.app..."
    xcrun notarytool submit "$APP_ZIP" \
        "${NOTARY_AUTH[@]}" \
        --wait
    rm -f "$APP_ZIP"

    echo "==> Stapling notarization ticket to $APP_NAME.app..."
    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"
fi

echo ""
echo "==> Creating DMG: $DMG_NAME..."
rm -f "$DMG_PATH"

TEMP_DMG="$OUTPUT_DIR/.tmp_seen.dmg"
rm -f "$TEMP_DMG"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$APP_BUNDLE" \
    -ov \
    -format UDRW \
    "$TEMP_DMG"

MOUNT_POINT=$(hdiutil attach "$TEMP_DMG" -readwrite -noverify -noautoopen | awk 'END {print $NF}')
ln -sf /Applications "$MOUNT_POINT/Applications"
hdiutil detach "$MOUNT_POINT" -quiet

hdiutil convert "$TEMP_DMG" -format UDZO -imagekey zlib-level=9 -o "$DMG_PATH"
rm -f "$TEMP_DMG"

echo "==> Signing DMG..."
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    echo ""
    echo "==> Notarizing DMG..."
    xcrun notarytool submit "$DMG_PATH" \
        "${NOTARY_AUTH[@]}" \
        --wait

    echo "==> Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"
fi

echo ""
echo "==> Verifying app..."
spctl --assess --verbose=4 --type execute "$APP_BUNDLE" 2>&1 || true

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
    echo "==> Verifying DMG..."
    spctl --assess --verbose=4 --type open --context context:primary-signature "$DMG_PATH" 2>&1 || true
fi

SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')

echo ""
echo "=========================================="
echo "  Done: $DMG_PATH"
echo "  Version: $VERSION"
echo "  SHA256:  $SHA256"
echo "=========================================="
