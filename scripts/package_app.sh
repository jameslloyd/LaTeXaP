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

# Embed standalone Tectonic binary inside Resources so the app is self-contained on any Mac
TECTONIC_CACHE="$PROJECT_DIR/.build/tectonic-standalone"
mkdir -p "$TECTONIC_CACHE"
if [[ ! -x "$TECTONIC_CACHE/tectonic" ]]; then
  echo "Downloading standalone statically-linked Tectonic engine..."
  curl -fsSL "https://github.com/tectonic-typesetting/tectonic/releases/download/tectonic%400.17.0/tectonic-0.17.0-aarch64-apple-darwin.tar.gz" | tar -xz -C "$TECTONIC_CACHE"
  chmod +x "$TECTONIC_CACHE/tectonic"
fi

if [[ -x "$TECTONIC_CACHE/tectonic" ]]; then
  echo "Embedding standalone Tectonic engine..."
  cp "$TECTONIC_CACHE/tectonic" "$RESOURCES_DIR/tectonic"
  chmod +x "$RESOURCES_DIR/tectonic"
elif command -v tectonic >/dev/null 2>&1; then
  TECTONIC_PATH="$(command -v tectonic)"
  echo "Embedding local Tectonic engine from $TECTONIC_PATH..."
  cp "$TECTONIC_PATH" "$RESOURCES_DIR/tectonic"
  chmod +x "$RESOURCES_DIR/tectonic"
fi
xattr -cr "$RESOURCES_DIR/tectonic" 2>/dev/null || true
codesign --force --sign - "$RESOURCES_DIR/tectonic"

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
    <string>0.1.2</string>
    <key>CFBundleVersion</key>
    <string>3</string>
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

# Strip any quarantine or extended attributes and deep ad-hoc sign the entire .app bundle
# so that Info.plist and Resources are properly bound and sealed.
xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict --verbose=2 "$APP_DIR"

touch "$APP_DIR"
echo "Created macOS application bundle at: $APP_DIR"

ZIP_PATH="$PROJECT_DIR/build/LaTeXaP-v0.1.2-macOS.zip"
LATEST_ZIP_PATH="$PROJECT_DIR/build/LaTeXaP-macOS.zip"
rm -f "$ZIP_PATH" "$LATEST_ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
cp "$ZIP_PATH" "$LATEST_ZIP_PATH"
echo "Created release zip archives at:"
echo "  - $ZIP_PATH"
echo "  - $LATEST_ZIP_PATH"
