#!/bin/bash
# Builds "What’s On.app" and a .dmg for Apple Silicon.
#   bash build.sh            → build/What’s On.app + build/WhatsOn.dmg
#   bash build.sh --install  → also copies the app to /Applications and opens it
#   bash build.sh --no-dmg   → skip the disk image (used by the in-app updater)
set -euo pipefail
cd "$(dirname "$0")"

INSTALL=0; MAKE_DMG=1
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --no-dmg) MAKE_DMG=0 ;;
    esac
done

APP_NAME="What’s On"
EXECUTABLE="WhatsOn"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"

if ! command -v swift >/dev/null 2>&1; then
    echo "Swift isn't installed. Run:  xcode-select --install   then run this script again."
    exit 1
fi

echo "→ Compiling (release, arm64)…"
swift build -c release --arch arm64
BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"

echo "→ Assembling app bundle…"
rm -rf "$BUILD_DIR"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Record where this build came from, so the app can update itself from the same repository.
if git rev-parse --git-dir >/dev/null 2>&1; then
    PLIST="$APP/Contents/Info.plist"
    COMMIT="$(git rev-parse HEAD)"
    REPO="$(git config --get remote.origin.url || true)"
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    /usr/libexec/PlistBuddy -c "Add :WOCommit string $COMMIT" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :WORepo string $REPO" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :WOBranch string $BRANCH" "$PLIST"
    echo "  built from $BRANCH @ ${COMMIT:0:7}"
fi

echo "→ Making icon…"
ICONSET="$BUILD_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "→ Signing (ad-hoc, for this Mac)…"
codesign --force --deep --sign - "$APP"

if [[ $MAKE_DMG == 1 ]]; then
    echo "→ Creating disk image…"
    STAGE="$BUILD_DIR/dmg"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$BUILD_DIR/WhatsOn.dmg" >/dev/null
    rm -rf "$STAGE"
fi

if [[ $INSTALL == 1 ]]; then
    echo "→ Installing to /Applications…"
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP" "/Applications/"
    open "/Applications/$APP_NAME.app"
fi

echo ""
echo "Done: $APP"
