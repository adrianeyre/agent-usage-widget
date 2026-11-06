#!/usr/bin/env bash
# Renders the website's PNG images into site/social/:
#   card.png             the 1200 × 630 link-preview card (Open Graph, X), drawn by
#                        scripts/social-card.swift around docs/images/widgets-dark.png
#   apple-touch-icon.png 180 × 180, and icon-192.png / icon-512.png for the web
#                        manifest, from site/favicon.svg
# They're committed, so the site build (on Linux) needs neither Swift nor macOS.
# Re-run this when the card's script, the favicon or the screenshots change. Needs a Mac.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=site/social
mkdir -p "$OUT"

swift scripts/social-card.swift "$PWD" "$OUT/card.png"

for size in 180 192 512; do
  name="icon-$size.png"
  [[ $size == 180 ]] && name=apple-touch-icon.png
  sips -s format png -z "$size" "$size" site/favicon.svg --out "$OUT/$name" >/dev/null
  echo "wrote $OUT/$name (${size}×${size})"
done
