#!/usr/bin/env bash
# Photographs every model in the game on a studio backdrop, one per PNG.
#
#   tools/render_models.sh <godot-binary> [output-dir]
#
# Runs under Xvfb with a software OpenGL rasteriser, because this environment
# has no GPU. See the header of tools/model_gallery.gd.

set -uo pipefail

GODOT="${1:?usage: render_models.sh <godot-binary> [output-dir]}"
OUT="${2:-captures/models}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$PROJECT_DIR/$OUT"
rm -f "$PROJECT_DIR/$OUT"/*.png

xvfb-run -a -s "-screen 0 560x560x24" \
  "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --resolution 560x560 \
  res://tools/model_gallery.tscn -- "--out=$PROJECT_DIR/$OUT" 2>&1 \
  | grep -vE "ALSA lib|libpulse|snd_|Could not set V-Sync|audio drivers failed|init_output_device"
