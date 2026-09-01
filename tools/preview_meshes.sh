#!/usr/bin/env bash
# Renders every MeshFactory shape to captures/meshes.png for visual review.
set -uo pipefail
GODOT="${1:?usage: preview_meshes.sh <godot-binary> [output-dir]}"
OUT="${2:-captures}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$PROJECT_DIR/$OUT"
xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --resolution 1280x720 \
  res://tools/mesh_preview.tscn -- "--out=$PROJECT_DIR/$OUT" 2>&1 \
  | grep -vE "ALSA lib|libpulse|snd_|V-Sync|audio drivers failed|init_output_device"
