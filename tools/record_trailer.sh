#!/usr/bin/env bash
# Records the trailer and encodes it to MP4.
#
#   tools/record_trailer.sh <godot-binary> [out.mp4] [duration-scale] [shots]
#
# Renders one PNG per video frame under Xvfb with a software rasteriser, then
# encodes with the ffmpeg bundled by the imageio-ffmpeg package. A duration
# scale below 1 shortens every shot, for a fast rehearsal.
#
# `shots` is a comma-separated list of shot indices - "13", or "4,13". Only those
# are rendered; the frames already on disk are kept and the new ones overwrite
# their own numbers, so one shot can be re-cut for a couple of minutes instead of
# re-rendering the whole film. The frame directory is NOT wiped in that mode.

set -uo pipefail

GODOT="${1:?usage: record_trailer.sh <godot-binary> [out.mp4] [duration-scale] [shots]}"
OUT="${2:-captures/trailer.mp4}"
SCALE="${3:-1.0}"
SHOTS="${4:-}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMES="$PROJECT_DIR/captures/trailer"

FFMPEG="$(python3 -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())' 2>/dev/null || true)"
if [ -z "$FFMPEG" ] || [ ! -x "$FFMPEG" ]; then
  FFMPEG="$(command -v ffmpeg || true)"
fi
if [ -z "$FFMPEG" ]; then
  echo "RESULT: FAIL - no ffmpeg. pip install imageio-ffmpeg" >&2
  exit 1
fi

if [ -z "$SHOTS" ]; then
  rm -rf "$FRAMES"
else
  # Re-cutting a subset. Wiping here would delete the sequence the new frames
  # are meant to slot into, and the encode would then be a few seconds long.
  if [ ! -d "$FRAMES" ]; then
    echo "RESULT: FAIL - no frames in $FRAMES to re-cut into" >&2
    exit 1
  fi
fi
mkdir -p "$FRAMES" "$(dirname "$PROJECT_DIR/$OUT")"

xvfb-run -a -s "-screen 0 1280x720x24" \
  "$GODOT" --path "$PROJECT_DIR" \
  --rendering-driver opengl3 --rendering-method gl_compatibility \
  --resolution 1280x720 \
  res://tools/trailer.tscn -- "--out=$FRAMES" "--scale=$SCALE" "--shots=$SHOTS" 2>&1 \
  | grep -vE "ALSA lib|libpulse|snd_|Could not set V-Sync|audio drivers failed|init_output_device"

COUNT=$(ls "$FRAMES"/*.png 2>/dev/null | wc -l)
if [ "$COUNT" -lt 2 ]; then
  echo "RESULT: FAIL - only $COUNT frames rendered" >&2
  exit 1
fi

# yuv420p and an even frame size, or the file will not play in half the world's
# video players.
"$FFMPEG" -y -loglevel error -framerate 24 -i "$FRAMES/f%05d.png" \
  -c:v libx264 -preset slow -crf 20 -pix_fmt yuv420p \
  -movflags +faststart "$PROJECT_DIR/$OUT"

echo "TRAILER $COUNT frames -> $OUT ($(du -h "$PROJECT_DIR/$OUT" | cut -f1))"
