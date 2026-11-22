#!/bin/zsh
# Compila el launcher y lo instala en /Applications/Tomodachi Launcher.app
set -euo pipefail
HERE=${0:A:h}
ROOT=${HERE:h}
APP="/Applications/Tomodachi Launcher.app"
GAME_APP="/Applications/Tomodachi Life.app"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/L.app/Contents/MacOS" "$TMP/L.app/Contents/Resources"

echo "== Compilando"
[ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun -sdk macosx swiftc -parse-as-library -swift-version 5 -O -target arm64-apple-macos14.0 \
  "$HERE/TomodachiLauncher.swift" -o "$TMP/L.app/Contents/MacOS/TomodachiLauncher"

# Usa el icono de la app del juego si existe
ICON_KEY=""
ICNS=$(ls "$GAME_APP/Contents/Resources/"*.icns 2>/dev/null | head -1 || true)
if [ -n "$ICNS" ]; then
  cp "$ICNS" "$TMP/L.app/Contents/Resources/AppIcon.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$TMP/L.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Tomodachi Launcher</string>
  <key>CFBundleDisplayName</key><string>Tomodachi Launcher</string>
  <key>CFBundleIdentifier</key><string>org.nxnative.tomodachi.launcher</string>
  <key>CFBundleExecutable</key><string>TomodachiLauncher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>TomogachiRoot</key><string>$ROOT</string>
  $ICON_KEY
</dict></plist>
EOF

codesign --force -s - "$TMP/L.app"
rm -rf "$APP"
mv "$TMP/L.app" "$APP"
echo "Listo: $APP"
