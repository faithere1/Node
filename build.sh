#!/bin/zsh
# Builds Node.app next to this script. Your note lives in
# ~/Library/Application Support/Node and is never touched by a rebuild.
set -e
cd "$(dirname "$0")"

APP=Node.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# App icon (same note symbol as the menu bar)
ICONSET="$(mktemp -d)/Node.iconset"
swift Tools/make_icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Node.icns"
rm -rf "$(dirname "$ICONSET")"

swiftc -O -swift-version 5 \
  -target "$(uname -m)-apple-macos13.0" \
  -o "$APP/Contents/MacOS/Node" \
  Sources/*.swift

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Node</string>
    <key>CFBundleDisplayName</key><string>Node</string>
    <key>CFBundleIdentifier</key><string>com.local.node</string>
    <key>CFBundleExecutable</key><string>Node</string>
    <key>CFBundleIconFile</key><string>Node</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>NSSupportsSuddenTermination</key><false/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $(pwd)/$APP"
