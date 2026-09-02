#!/usr/bin/env bash
# Photographs every interface screen.
#
#   tools/render_ui.sh <godot-binary> [output-dir]
set -uo pipefail
GODOT="${1:?usage: render_ui.sh <godot-binary> [output-dir]}"
OUT="${2:-captures/ui}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$PROJECT_DIR/$OUT"
rm -f "$PROJECT_DIR/$OUT"/*.png
xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --resolution 1280x720 \
  res://tools/ui_gallery.tscn -- "--out=$PROJECT_DIR/$OUT" 2>&1 \
  | grep -vE "ALSA lib|libpulse|snd_|Could not set V-Sync|audio drivers failed|init_output_device"
