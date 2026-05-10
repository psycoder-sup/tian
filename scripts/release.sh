#!/bin/bash
set -euo pipefail

# Build → DMG → notarize → staple → verify.
#
# Usage:
#   scripts/release.sh [version]
#
# Environment:
#   NOTARY_PROFILE   Keychain profile name for `xcrun notarytool` (default: tian-notary)
#                    Set up once with: xcrun notarytool store-credentials
#   SKIP_NOTARIZE=1  Skip notarization + stapling (useful for local test builds)
#
# Output: .build/release/tian-<version>.dmg (+ .sha256)

VERSION="${1:-$(git describe --tags --always --dirty 2>/dev/null || echo dev)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-tian-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."

RELEASE_DIR=".build/release"
APP_PATH=".build/Build/Products/Release/tian.app"
DMG_PATH="$RELEASE_DIR/tian-$VERSION.dmg"
IDENTITY="Developer ID Application: Sanguk Park (S5UNLP3V56)"

echo "==> Release $VERSION"
mkdir -p "$RELEASE_DIR"

echo "==> xcodegen generate"
xcodegen generate

echo "==> xcodebuild Release (signed)"
xcodebuild \
  -project tian.xcodeproj \
  -scheme tian \
  -configuration Release \
  -derivedDataPath .build \
  build

echo "==> Verify app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Timestamp|Runtime"

echo "==> Build DMG"
rm -f "$DMG_PATH"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP_PATH" "$STAGING/"
create-dmg \
  --volname "tian $VERSION" \
  --window-size 540 380 \
  --icon-size 128 \
  --icon "tian.app" 140 190 \
  --app-drop-link 400 190 \
  --no-internet-enable \
  "$DMG_PATH" \
  "$STAGING"

echo "==> Sign DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  echo "==> Skipping notarization (SKIP_NOTARIZE=1)"
  echo "    Users will see Gatekeeper warnings on first launch."
else
  echo "==> Notarize (this can take a few minutes)"
  SUBMIT_OUT="$(xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait --output-format json)"
  echo "$SUBMIT_OUT"
  STATUS="$(echo "$SUBMIT_OUT" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("status",""))')"
  SUBMIT_ID="$(echo "$SUBMIT_OUT" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("id",""))')"
  if [[ "$STATUS" != "Accepted" ]]; then
    echo "Notarization failed: status=$STATUS" >&2
    if [[ -n "$SUBMIT_ID" ]]; then
      echo "Fetching Apple log:" >&2
      xcrun notarytool log "$SUBMIT_ID" --keychain-profile "$NOTARY_PROFILE" >&2 || true
    fi
    exit 1
  fi

  echo "==> Staple ticket"
  xcrun stapler staple "$DMG_PATH"

  echo "==> Gatekeeper assessment"
  spctl -a -t open --context context:primary-signature -v "$DMG_PATH"
fi

echo "==> SHA-256"
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"

echo
echo "Done: $DMG_PATH"
