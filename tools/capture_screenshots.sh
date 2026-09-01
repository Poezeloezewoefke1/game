#!/usr/bin/env bash
# Renders the game to PNG files for visual review.
#
#   tools/capture_screenshots.sh <godot-binary> [output-dir] [scene-key]
#
# Passing a scene key ("hub" or "nerava") shoots only that scene.
#
# Runs under Xvfb with a software OpenGL rasteriser, because this environment
# has no GPU and no Vulkan driver. See the header of tools/screenshot.gd for
# what that does and does not reproduce faithfully.

set -uo pipefail

GODOT="${1:?usage: capture_screenshots.sh <godot-binary> [output-dir]}"
OUT="${2:-captures}"
ONLY="${3:-}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

mkdir -p "$PROJECT_DIR/$OUT"
if [ -z "$ONLY" ]; then rm -f "$PROJECT_DIR/$OUT"/*.png; fi

xvfb-run -a -s "-screen 0 960x540x24" \
  "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --resolution 960x540 \
  res://tools/screenshot.tscn -- "--out=$PROJECT_DIR/$OUT" "--only=$ONLY" 2>&1 \
  | grep -vE "ALSA lib|libpulse|snd_|Could not set V-Sync|audio drivers failed|init_output_device"

echo "---"
ls -la "$PROJECT_DIR/$OUT"/*.png 2>/dev/null | wc -l | xargs echo "images:"
