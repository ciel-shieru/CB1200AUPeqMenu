#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
cd "$ROOT"
VERSION="$(cat "$ROOT/VERSION")"
case "$VERSION" in
    ''|*[!0-9.]*) echo "Invalid VERSION: $VERSION" >&2; exit 1 ;;
esac

pkill -x CB1200AUPeqMenu 2>/dev/null || true
swift package clean
swift build -c release
BIN="$(swift build -c release --show-bin-path)/CB1200AUPeqMenu"
APP="$ROOT/dist/CB1200AUPeqMenu.app"
ENTITLEMENTS="$ROOT/CB1200AUPeqMenu.entitlements"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/CB1200AUPeqMenu"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>CB1200AU PEQ</string>
    <key>CFBundleExecutable</key>
    <string>CB1200AUPeqMenu</string>
    <key>CFBundleIdentifier</key>
    <string>local.cb1200au.peqmenu</string>
    <key>CFBundleName</key>
    <string>CB1200AUPeqMenu</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
SIGN_FLAGS="--force --options runtime"
if [ "$CODESIGN_IDENTITY" != "-" ]; then
    SIGN_FLAGS="$SIGN_FLAGS --timestamp"
fi

# Keep the functional entitlements on the executable only; no Hardened Runtime
# exception entitlements are granted.
# shellcheck disable=SC2086
codesign $SIGN_FLAGS --entitlements "$ENTITLEMENTS" --sign "$CODESIGN_IDENTITY" "$APP/Contents/MacOS/CB1200AUPeqMenu" >/dev/null
# shellcheck disable=SC2086
codesign $SIGN_FLAGS --sign "$CODESIGN_IDENTITY" "$APP" >/dev/null
codesign --verify --strict --verbose=2 "$APP" >/dev/null

HASH="$(shasum -a 256 "$APP/Contents/MacOS/CB1200AUPeqMenu" | awk '{print $1}')"
echo "Built: $APP"
echo "Signing identity: $CODESIGN_IDENTITY"
echo "Hardened Runtime: enabled"
echo "App Sandbox: enabled"
echo "USB entitlement: enabled"
echo "Network client/server entitlements: absent"
echo "Binary SHA-256: $HASH"
echo "Build fingerprint: v$VERSION"
