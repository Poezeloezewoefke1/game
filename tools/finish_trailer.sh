#!/usr/bin/env bash
# Grades the rendered frames, mixes in the score and voice, and encodes the
# finished trailer.
#
#   tools/finish_trailer.sh [out.mp4] [crf]
#
# Expects captures/trailer/f%05d.png to exist (tools/record_trailer.sh writes
# them) and builds the audio from scratch with tools/audio/build_audio.py.

set -uo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMES="$PROJECT_DIR/captures/trailer"
OUT="${1:-captures/starbound-station-trailer.mp4}"
CRF="${2:-24}"
MIX="$PROJECT_DIR/captures/audio/mix.wav"
FPS=24

FFMPEG="$(python3 -c 'import imageio_ffmpeg; print(imageio_ffmpeg.get_ffmpeg_exe())' 2>/dev/null || true)"
[ -x "${FFMPEG:-}" ] || FFMPEG="$(command -v ffmpeg || true)"
if [ -z "$FFMPEG" ]; then
  echo "RESULT: FAIL - no ffmpeg. pip install imageio-ffmpeg" >&2
  exit 1
fi

COUNT=$(ls "$FRAMES"/*.png 2>/dev/null | wc -l)
if [ "$COUNT" -lt 2 ]; then
  echo "RESULT: FAIL - only $COUNT frames in $FRAMES" >&2
  exit 1
fi
SECONDS_TOTAL=$(python3 -c "print('%.3f' % ($COUNT / $FPS))")

mkdir -p "$(dirname "$MIX")"
python3 "$PROJECT_DIR/tools/audio/build_audio.py" --out "$MIX" \
  --seconds "$SECONDS_TOTAL" --report || exit 1

# The grade. Deliberately restrained: the levels are already lit, and a heavy
# LUT on top of good lighting reads as a filter rather than as photography.
#
#   curves   a gentle S with NO black lift, so the cuts to black stay black -
#            lifting them turns every act break into dark grey
#   balance  cool shadows, faintly warm highlights
#   vignette pulls the eye off the edges of a 16:9 frame
#   noise    a little grain; the renderer's output is otherwise clinically clean
#   drawbox  fresh pure-black letterbox over the baked-in bars, because the
#            vignette and grain would otherwise crawl across them
GRADE="eq=contrast=1.10:brightness=-0.015:saturation=0.80,\
curves=all='0/0 0.22/0.17 0.5/0.5 0.8/0.84 1/1',\
colorbalance=rs=-0.05:bs=0.09:gs=-0.01:rm=-0.02:bm=0.03:rh=0.03:bh=-0.02,\
vignette=angle=PI/4.4,\
noise=alls=4:allf=t+u,\
drawbox=x=0:y=0:w=iw:h=62:color=black@1.0:t=fill,\
drawbox=x=0:y=ih-62:w=iw:h=62:color=black@1.0:t=fill,\
format=yuv420p"

"$FFMPEG" -y -loglevel error \
  -framerate "$FPS" -i "$FRAMES/f%05d.png" \
  -i "$MIX" \
  -vf "$GRADE" \
  -c:v libx264 -preset slow -crf "$CRF" -tune animation -pix_fmt yuv420p \
  -c:a aac -b:a 192k -ac 2 \
  -movflags +faststart -shortest \
  "$PROJECT_DIR/$OUT" || exit 1

echo "TRAILER $COUNT frames / ${SECONDS_TOTAL}s -> $OUT ($(du -h "$PROJECT_DIR/$OUT" | cut -f1))"
