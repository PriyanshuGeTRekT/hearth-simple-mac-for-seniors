#!/bin/bash
# Builds dist/Hearth.app (ad-hoc signed) and a zip.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${VERSION:-1.0.0}"
swift build -c release 2>&1 | grep -E "error:|Build complete" | tail -3
BIN=.build/release
APP=dist/Hearth.app
rm -rf dist && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/Hearth" "$APP/Contents/MacOS/Hearth"
ICONSET="$(mktemp -d)/Hearth.iconset"
"$BIN/Hearth" --make-icon "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.hearth.mac</string>
  <key>CFBundleName</key><string>Hearth</string>
  <key>CFBundleDisplayName</key><string>Hearth</string>
  <key>CFBundleExecutable</key><string>Hearth</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSSupportsAutomaticTermination</key><false/>
  <key>NSSupportsSuddenTermination</key><false/>
  <key>NSHumanReadableCopyright</key><string>Hearth — a calm, simple home for the Mac.</string>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null
codesign --force --deep --sign - "$APP" 2>&1 | tail -1
codesign --verify --deep --strict "$APP" && echo "signature OK (ad-hoc)"
(cd dist && ditto -c -k --keepParent Hearth.app Hearth.zip && ditto -c -k --keepParent Hearth.app "Hearth-$VERSION.zip")
echo "built: $APP ($(du -sh "$APP" | cut -f1)), dist/Hearth-$VERSION.zip"
