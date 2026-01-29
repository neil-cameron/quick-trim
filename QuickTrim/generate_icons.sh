#!/bin/bash

# Generate App Icons from SVG
# Requires: brew install librsvg (for rsvg-convert)
# Or use online converter if rsvg-convert not available

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_DIR="$SCRIPT_DIR/QuickTrim/Assets.xcassets/AppIcon.appiconset"
SVG_FILE="$ICON_DIR/QuickTrimIcon.svg"

# Check if rsvg-convert is available
if command -v rsvg-convert &> /dev/null; then
    echo "Using rsvg-convert to generate icons..."

    # Generate all required sizes
    # macOS requires: 16, 32, 64, 128, 256, 512, 1024
    sizes=(16 32 64 128 256 512 1024)

    for size in "${sizes[@]}"; do
        output="$ICON_DIR/icon_${size}x${size}.png"
        rsvg-convert -w $size -h $size "$SVG_FILE" -o "$output"
        echo "Generated: icon_${size}x${size}.png"
    done

    echo ""
    echo "Icons generated! Now update Contents.json with the filenames:"
    echo "  16x16@1x  -> icon_16x16.png"
    echo "  16x16@2x  -> icon_32x32.png"
    echo "  32x32@1x  -> icon_32x32.png"
    echo "  32x32@2x  -> icon_64x64.png"
    echo "  128x128@1x -> icon_128x128.png"
    echo "  128x128@2x -> icon_256x256.png"
    echo "  256x256@1x -> icon_256x256.png"
    echo "  256x256@2x -> icon_512x512.png"
    echo "  512x512@1x -> icon_512x512.png"
    echo "  512x512@2x -> icon_1024x1024.png"
else
    echo "rsvg-convert not found."
    echo "Install with: brew install librsvg"
    echo ""
    echo "Alternatively, use an online SVG to PNG converter:"
    echo "1. Open QuickTrimIcon.svg in a browser"
    echo "2. Use https://cloudconvert.com/svg-to-png or similar"
    echo "3. Generate PNGs at sizes: 16, 32, 64, 128, 256, 512, 1024"
    echo "4. Save them as icon_NxN.png in the AppIcon.appiconset folder"
fi
