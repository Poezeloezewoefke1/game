#!/usr/bin/env bash
# Drives a real play session with simulated keyboard and mouse input.
#
#   tools/run_playtest.sh <godot> [strategy] [out.log]
#
# Runs headless: Input.action_press() and InputEventMouseMotion work without a
# display server, and the player's own input path is what consumes them.
set -uo pipefail
GODOT="${1:?usage: run_playtest.sh <godot> [strategy] [out.log]}"
STRATEGY="${2:-cautious}"
OUT="${3:-ci-logs/playtest-$STRATEGY.log}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# An absolute --out is taken as given. Joining it to the project directory
# silently wrote /home/user/game/tmp/... for a caller who asked for /tmp/...,
# and then the log everyone was tailing never appeared.
case "$OUT" in
  /*) OUT_PATH="$OUT" ;;
  *)  OUT_PATH="$PROJECT_DIR/$OUT" ;;
esac
mkdir -p "$(dirname "$OUT_PATH")"
"$GODOT" --headless --path "$PROJECT_DIR" res://tools/playtest.tscn -- \
  "--strategy=$STRATEGY" "--out=$OUT_PATH" 2>&1 \
  | grep -vE "ALSA lib|libpulse|snd_|audio drivers failed"
exit "${PIPESTATUS[0]}"
