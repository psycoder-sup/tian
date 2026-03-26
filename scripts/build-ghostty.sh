#!/bin/bash
set -euo pipefail

# Build libghostty-vt from source and vendor into the aterm project.
#
# Prerequisites:
#   brew install zig
#
# Usage:
#   ./scripts/build-ghostty.sh [--clean]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/aterm/Vendor/ghostty"
GHOSTTY_DIR="$PROJECT_ROOT/.ghostty-src"

# Parse args
CLEAN=false
for arg in "$@"; do
    case "$arg" in
        --clean) CLEAN=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

# Check zig is installed
if ! command -v zig &>/dev/null; then
    echo "Error: zig is not installed. Run: brew install zig"
    exit 1
fi

echo "zig version: $(zig version)"

# Clone or update ghostty
if [ "$CLEAN" = true ] && [ -d "$GHOSTTY_DIR" ]; then
    echo "Cleaning ghostty source..."
    rm -rf "$GHOSTTY_DIR"
fi

if [ ! -d "$GHOSTTY_DIR" ]; then
    echo "Cloning ghostty..."
    git clone --depth 1 https://github.com/ghostty-org/ghostty.git "$GHOSTTY_DIR"
else
    echo "Ghostty source already exists at $GHOSTTY_DIR"
    echo "  Use --clean to re-clone, or delete manually to update."
fi

# Build libghostty-vt static library
echo "Building libghostty-vt (this may take a few minutes)..."

# macOS 26 SDK's .tbd files use arm64e only, which Zig's LLD can't handle.
# Use the CommandLineTools SDK (macOS 15) which includes arm64 targets.
BUILD_ENV=""
if [ -d "/Library/Developer/CommandLineTools/SDKs" ]; then
    # Find the newest non-26 SDK
    CLT_SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX1*.sdk 2>/dev/null | sort -V | tail -1)
    if [ -n "$CLT_SDK" ]; then
        echo "Using SDK: $CLT_SDK (workaround for macOS 26 Zig compatibility)"
        BUILD_ENV="DEVELOPER_DIR=/Library/Developer/CommandLineTools"
    fi
fi

(
    cd "$GHOSTTY_DIR"
    eval $BUILD_ENV zig build -Demit-lib-vt=true -Doptimize=ReleaseFast -Dsimd=false
)

# Verify build output
BUILT_LIB="$GHOSTTY_DIR/zig-out/lib/libghostty-vt.a"
BUILT_HEADERS="$GHOSTTY_DIR/zig-out/include/ghostty"

if [ ! -f "$BUILT_LIB" ]; then
    echo "Error: libghostty-vt.a not found at $BUILT_LIB"
    exit 1
fi

if [ ! -d "$BUILT_HEADERS" ]; then
    echo "Error: headers not found at $BUILT_HEADERS"
    exit 1
fi

echo "Build successful."

# Repack the archive with Apple's libtool for proper 8-byte alignment.
# Zig's ar produces archives that Apple's ld rejects.
echo "Repacking archive for Apple linker compatibility..."
REPACK_DIR=$(mktemp -d)
trap "rm -rf '$REPACK_DIR'" EXIT

(
    cd "$REPACK_DIR"
    ar x "$BUILT_LIB"
    chmod 644 *.o
)

mkdir -p "$VENDOR_DIR/lib"
libtool -static -o "$VENDOR_DIR/lib/libghostty-vt.a" "$REPACK_DIR"/*.o 2>/dev/null

# Copy headers
echo "Copying headers..."
rm -rf "$VENDOR_DIR/include/ghostty"
mkdir -p "$VENDOR_DIR/include"
cp -R "$BUILT_HEADERS" "$VENDOR_DIR/include/"

# Verify
echo ""
echo "Vendored artifacts:"
echo "  Library: $VENDOR_DIR/lib/libghostty-vt.a ($(du -h "$VENDOR_DIR/lib/libghostty-vt.a" | cut -f1))"
echo "  Headers: $VENDOR_DIR/include/ghostty/"
ls "$VENDOR_DIR/include/ghostty/vt/" | head -5
echo "  ... ($(ls "$VENDOR_DIR/include/ghostty/vt/" | wc -l | tr -d ' ') header files)"
echo ""
echo "Done. Run 'xcodegen generate' to update the Xcode project."
