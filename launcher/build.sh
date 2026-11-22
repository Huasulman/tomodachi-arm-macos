#!/bin/zsh
# 編譯啟動器並裝到 /Applications/Tomodachi Launcher.app（指向本倉）；加 --dist <目錄> 則打成可分發的 zip
# Builds the launcher into /Applications/Tomodachi Launcher.app (pointing at this repo); with --dist <dir> it packs a distributable zip instead
#   launcher/build.sh                 安裝給自己用 | install for yourself
#   launcher/build.sh --dist <目錄>   可分發版：不寫本機路徑、不帶遊戲圖標 | distributable: no local path, no game icon
set -euo pipefail
HERE=${0:A:h}
ROOT=${HERE:h}
APP="/Applications/Tomodachi Launcher.app"
GAME_APP="/Applications/Tomodachi Life.app"
VERSION=1.1

DIST=""
if [ "${1:-}" = "--dist" ]; then
  DIST=${2:?--dist 需要輸出目錄 | --dist needs an output folder}
  mkdir -p "$DIST"; DIST=${DIST:A}
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
L="$TMP/Tomodachi Launcher.app"
mkdir -p "$L/Contents/MacOS" "$L/Contents/Resources"

echo "== 編譯 | compiling"
[ -d /Applications/Xcode.app ] && export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcrun -sdk macosx swiftc -parse-as-library -swift-version 5 -O -target arm64-apple-macos14.0 \
  "$HERE/TomodachiLauncher.swift" -o "$L/Contents/MacOS/TomodachiLauncher"

# 自用版借遊戲 App 的圖標（任天堂素材，可分發版不帶）
# The local build borrows the game app's icon (Nintendo artwork, left out of the distributable build)
ICON_KEY=""
ICNS=$(ls "$GAME_APP/Contents/Resources/"*.icns 2>/dev/null | head -1 || true)
if [ -z "$DIST" ] && [ -n "$ICNS" ]; then
  cp "$ICNS" "$L/Contents/Resources/AppIcon.icns"
  ICON_KEY="<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

# 自用版記下本倉路徑；可分發版不寫，首次打開時讓使用者選倉庫目錄
# The local build records this repo's path; the distributable one leaves it out and asks for the repo folder on first launch
ROOT_KEY=""
[ -z "$DIST" ] && ROOT_KEY="<key>TomogachiRoot</key><string>$ROOT</string>"

cat > "$L/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Tomodachi Launcher</string>
  <key>CFBundleDisplayName</key><string>Tomodachi Launcher</string>
  <key>CFBundleIdentifier</key><string>org.nxnative.tomodachi.launcher</string>
  <key>CFBundleExecutable</key><string>TomodachiLauncher</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  $ROOT_KEY
  $ICON_KEY
</dict></plist>
EOF

codesign --force -s - "$L"

if [ -n "$DIST" ]; then
  ZIP="$DIST/Tomodachi-Launcher-$VERSION-arm64.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$L" "$ZIP"
  echo "完成 | done: $ZIP"
else
  rm -rf "$APP"
  mv "$L" "$APP"
  echo "完成 | done: $APP"
fi
