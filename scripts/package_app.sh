#!/usr/bin/env zsh
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

echo "Building LaTeXaP (Release)..."
swift build -c release

APP_DIR="$PROJECT_DIR/build/LaTeXaP.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$PROJECT_DIR/.build/release/LaTeXaP" "$MACOS_DIR/LaTeXaP"
chmod +x "$MACOS_DIR/LaTeXaP"

# Embed AppIcon.icns and AppIcon-1024.png
if [[ -f "$PROJECT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$PROJECT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [[ -f "$PROJECT_DIR/Resources/AppIcon-1024.png" ]]; then
  cp "$PROJECT_DIR/Resources/AppIcon-1024.png" "$RESOURCES_DIR/AppIcon-1024.png"
fi

# Embed Tectonic binary inside Resources so the app is self-contained
if command -v tectonic >/dev/null 2>&1; then
  TECTONIC_PATH="$(command -v tectonic)"
  echo "Embedding Tectonic engine from $TECTONIC_PATH..."
  cp "$TECTONIC_PATH" "$RESOURCES_DIR/tectonic"
  chmod +x "$RESOURCES_DIR/tectonic"
fi

cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>LaTeXaP</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.latexap.studio</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>LaTeXaP</string>
    <key>CFBundleDisplayName</key>
    <string>LaTeXaP</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>NSHumanReadableCopyright</key>
    <string>https://github.com/jameslloyd/LaTeXaP.git</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
EOF

touch "$APP_DIR"
echo "Created macOS application bundle at: $APP_DIR"

ZIP_PATH="$PROJECT_DIR/build/LaTeXaP-v0.1-macOS.zip"
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
echo "Created release zip archive at: $ZIP_PATH"
