#!/bin/bash

set -euo pipefail

# Generate macOS app icons.
# Default source: ../Icon/improved_icon.png
# Optional SVG fallback: --svg

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ICON_DIR="$SCRIPT_DIR/QuickTrim/Assets.xcassets/AppIcon.appiconset"
SVG_FILE="$ICON_DIR/QuickTrimIcon.svg"
PNG_FILE="$SCRIPT_DIR/../Icon/improved_icon.png"

# Approximate macOS app icon corner curvature for pre-masked source images.
CORNER_RATIO="0.22"
SIZES=(16 32 64 128 256 512 1024)

generate_from_png() {
    local source_png="$1"
    local size="$2"
    local output="$3"
    local radius
    radius=$(awk "BEGIN { printf \"%.4f\", $size * $CORNER_RATIO }")

    ffmpeg -v error -y -i "$source_png" \
        -vf "scale=${size}:${size}:flags=lanczos,format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lte(pow(max(max(${radius}-X,0),X-(W-${radius})),2)+pow(max(max(${radius}-Y,0),Y-(H-${radius})),2),pow(${radius},2)),255,0)'" \
        -frames:v 1 "$output"
}

if [[ "${1:-}" == "--svg" ]]; then
    if ! command -v rsvg-convert >/dev/null 2>&1; then
        echo "rsvg-convert not found. Install with: brew install librsvg"
        exit 1
    fi

    echo "Using SVG source: $SVG_FILE"
    for size in "${SIZES[@]}"; do
        output="$ICON_DIR/icon_${size}x${size}.png"
        rsvg-convert -w "$size" -h "$size" "$SVG_FILE" -o "$output"
        echo "Generated: icon_${size}x${size}.png"
    done
    exit 0
fi

if [[ ! -f "$PNG_FILE" ]]; then
    echo "PNG source not found: $PNG_FILE"
    echo "Pass --svg to use QuickTrimIcon.svg instead."
    exit 1
fi

if ! command -v ffmpeg >/dev/null 2>&1; then
    echo "ffmpeg not found; cannot round-mask PNG icon source."
    exit 1
fi

echo "Using PNG source with rounded alpha mask: $PNG_FILE"
for size in "${SIZES[@]}"; do
    output="$ICON_DIR/icon_${size}x${size}.png"
    generate_from_png "$PNG_FILE" "$size" "$output"
    echo "Generated: icon_${size}x${size}.png"
done

echo "Done. AppIcon assets updated in: $ICON_DIR"
