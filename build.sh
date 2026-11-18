#!/bin/bash
# Build Dictate.app.
#
#   ./build.sh              build, sign, and install to /Applications
#   ./build.sh --no-install build only (output: build/Dictate.app)
#   ./build.sh --zip        also create build/Dictate-<version>.zip (for releases)
#
# Signing: uses the certificate named by $CODESIGN_IDENTITY (default "DictateLocal") if it exists,
# otherwise falls back to ad-hoc signing. A stable certificate keeps macOS privacy permissions
# (Microphone, Accessibility, Input Monitoring) across rebuilds; create one with scripts/setup-signing.sh.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="2.0.0"
IDENTITY="${CODESIGN_IDENTITY:-DictateLocal}"
APP="build/Dictate.app"
INSTALL=1; ZIP=0
for arg in "$@"; do
  case "$arg" in
    --no-install) INSTALL=0 ;;
    --zip) ZIP=1 ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done

rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# -file-prefix-map keeps the build machine's folder names out of the binary.
swift build -c release \
  -Xswiftc -file-prefix-map -Xswiftc "$PWD=." \
  -Xswiftc -file-prefix-map -Xswiftc "$HOME=~" 2>&1 | grep -E "error|Build complete" || true
cp .build/release/Dictate "$APP/Contents/MacOS/Dictate"
strip -Sx "$APP/Contents/MacOS/Dictate"

# App icon (generated, no binary assets in the repo)
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf build/AppIcon.iconset

cat > "$APP/Contents/Info.plist" <<P
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Dictate</string>
<key>CFBundleDisplayName</key><string>Dictate</string>
<key>CFBundleExecutable</key><string>Dictate</string>
<key>CFBundleIdentifier</key><string>local.dictate</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$VERSION</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Dictate listens to your voice to turn it into text.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
P

if security find-identity -p codesigning 2>/dev/null | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
  echo "signed with \"$IDENTITY\""
else
  codesign --force --sign - "$APP"
  echo "signed ad-hoc (macOS will ask for permissions again after every rebuild; see scripts/setup-signing.sh)"
fi

if [ "$ZIP" = 1 ]; then
  ditto -c -k --keepParent "$APP" "build/Dictate-$VERSION.zip"
  echo "created build/Dictate-$VERSION.zip"
fi

if [ "$INSTALL" = 1 ]; then
  pkill -x Dictate 2>/dev/null || true
  sleep 0.5
  rm -rf /Applications/Dictate.app
  cp -R "$APP" /Applications/Dictate.app
  echo "installed /Applications/Dictate.app"
fi
