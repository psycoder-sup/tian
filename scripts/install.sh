#!/bin/bash
set -euo pipefail

APP_NAME="tian.app"
SOURCE=".build/Build/Products/Release/$APP_NAME"
DEST="/Applications/$APP_NAME"

if [ ! -d "$SOURCE" ]; then
  echo "Error: Release build not found at $SOURCE"
  echo "Run: xcodebuild -project tian.xcodeproj -scheme tian -configuration Release -derivedDataPath .build build"
  exit 1
fi

echo "Removing $DEST..."
rm -rf "$DEST"

echo "Copying $SOURCE → $DEST..."
cp -R "$SOURCE" "$DEST"

echo "Done. Installed $(defaults read "$DEST/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo 'unknown version') to /Applications/"
