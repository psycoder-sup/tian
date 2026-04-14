#!/bin/bash
set -euo pipefail

CONFIG="${1:-Debug}"

case "$CONFIG" in
  Debug|Release) ;;
  debug) CONFIG="Debug" ;;
  release) CONFIG="Release" ;;
  *)
    echo "Usage: $0 [Debug|Release]" >&2
    exit 1
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild -configuration $CONFIG"
xcodebuild \
  -project tian.xcodeproj \
  -scheme tian \
  -configuration "$CONFIG" \
  -derivedDataPath .build \
  build
