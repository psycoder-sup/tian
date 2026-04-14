#!/bin/bash
set -euo pipefail

# Build GhosttyKit.xcframework from source and vendor into the tian project.
#
# Prerequisites:
#   brew install zig
#
# Usage:
#   ./scripts/build-ghostty.sh [--clean]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$PROJECT_ROOT/tian/Vendor"
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

# macOS 26 SDK's .tbd files use arm64e only, which Zig's LLD can't handle.
# Use the CommandLineTools SDK (macOS 15) which includes arm64 targets.
BUILD_ENV=""
if [ -d "/Library/Developer/CommandLineTools/SDKs" ]; then
    CLT_SDK=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX1*.sdk 2>/dev/null | sort -V | tail -1)
    if [ -n "$CLT_SDK" ]; then
        echo "Using SDK: $CLT_SDK (workaround for macOS 26 Zig compatibility)"
        BUILD_ENV="DEVELOPER_DIR=/Library/Developer/CommandLineTools"
        # CLT SDK lacks metal compiler. Find it from Xcode and pass via env vars
        # so the patched MetallibStep.zig can use it directly.
        METAL_PATH=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcrun --find metal 2>/dev/null || true)
        METALLIB_PATH=$(DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/xcrun --find metallib 2>/dev/null || true)
        if [ -n "$METAL_PATH" ]; then
            echo "Metal compiler: $METAL_PATH"
            BUILD_ENV="$BUILD_ENV GHOSTTY_METAL_PATH=$METAL_PATH"
        fi
        if [ -n "$METALLIB_PATH" ]; then
            echo "Metallib tool: $METALLIB_PATH"
            BUILD_ENV="$BUILD_ENV GHOSTTY_METALLIB_PATH=$METALLIB_PATH"
        fi
        # xcodebuild requires full Xcode, not CLT
        XCODEBUILD_PATH="/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild"
        if [ -x "$XCODEBUILD_PATH" ]; then
            echo "Xcodebuild: $XCODEBUILD_PATH"
            BUILD_ENV="$BUILD_ENV GHOSTTY_XCODEBUILD_PATH=$XCODEBUILD_PATH"
        fi
    fi
fi

# Build GhosttyKit xcframework (full ghostty library with rendering, PTY, etc.)
echo "Building GhosttyKit.xcframework (this may take several minutes)..."
(
    cd "$GHOSTTY_DIR"
    eval $BUILD_ENV zig build \
        -Demit-xcframework=true \
        -Dxcframework-target=native \
        -Doptimize=ReleaseFast
)

# Verify build output - xcframework is output to macos/ dir, not zig-out/
BUILT_XCFW="$GHOSTTY_DIR/macos/GhosttyKit.xcframework"
BUILT_RESOURCES="$GHOSTTY_DIR/zig-out/share/ghostty"

if [ ! -d "$BUILT_XCFW" ]; then
    echo "Error: GhosttyKit.xcframework not found at $BUILT_XCFW"
    exit 1
fi

echo "Build successful."

# Remove old vendor artifacts
echo "Removing old vendor artifacts..."
rm -rf "$VENDOR_DIR/ghostty"
rm -f "$VENDOR_DIR/ghostty.h"
rm -rf "$VENDOR_DIR/GhosttyKit.xcframework"

# Copy xcframework
echo "Copying GhosttyKit.xcframework..."
cp -R "$BUILT_XCFW" "$VENDOR_DIR/"

# Extract and copy the header file
echo "Copying ghostty.h header..."
# The header is inside the xcframework under Headers/
HEADER_PATH=$(find "$BUILT_XCFW" -name "ghostty.h" -type f | head -1)
if [ -n "$HEADER_PATH" ]; then
    cp "$HEADER_PATH" "$VENDOR_DIR/ghostty.h"
else
    # Fallback: check zig-out/include
    if [ -f "$GHOSTTY_DIR/zig-out/include/ghostty.h" ]; then
        cp "$GHOSTTY_DIR/zig-out/include/ghostty.h" "$VENDOR_DIR/ghostty.h"
    else
        echo "Warning: ghostty.h not found in xcframework or zig-out/include"
        echo "You may need to copy it manually from cmux or the ghostty project."
    fi
fi

# Copy resources (shell integration, terminfo, etc.)
if [ -d "$BUILT_RESOURCES" ]; then
    echo "Copying ghostty resources..."
    rm -rf "$VENDOR_DIR/resources"
    mkdir -p "$VENDOR_DIR/resources"
    cp -R "$BUILT_RESOURCES"/* "$VENDOR_DIR/resources/"
else
    echo "Warning: ghostty resources not found at $BUILT_RESOURCES"
fi

# Verify
echo ""
echo "Vendored artifacts:"
echo "  XCFramework: $VENDOR_DIR/GhosttyKit.xcframework"
du -sh "$VENDOR_DIR/GhosttyKit.xcframework" | awk '{print "    Size: "$1}'
if [ -f "$VENDOR_DIR/ghostty.h" ]; then
    echo "  Header: $VENDOR_DIR/ghostty.h ($(wc -l < "$VENDOR_DIR/ghostty.h") lines)"
fi
if [ -d "$VENDOR_DIR/resources" ]; then
    echo "  Resources: $VENDOR_DIR/resources/"
fi
echo ""
echo "Done."
