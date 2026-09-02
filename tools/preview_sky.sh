#!/usr/bin/env bash
# Renders the sky shader on its own from several directions.
#
#   tools/preview_sky.sh <godot-binary> [output-dir]
#
# Runs under Xvfb with a software rasteriser; see tools/screenshot.gd.
set -uo pipefail
GODOT="${1:?usage: preview_sky.sh <godot-binary> [output-dir]}"
OUT="${2:-captures/sky}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$PROJECT_DIR/$OUT"
rm -f "$PROJECT_DIR/$OUT"/*.png
xvfb-run -a -s "-screen 0 720x405x24" \
  "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --resolution 720x405 \
  res://tools/sky_preview.tscn -- "--out=$PROJECT_DIR/$OUT" 2>&1 \
  | grep -vE "ALSA lib|libpulse|snd_|Could not set V-Sync|audio drivers failed|init_output_device"
