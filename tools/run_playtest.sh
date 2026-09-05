#!/usr/bin/env bash
# Drives a real play session with simulated keyboard and mouse input.
#
#   tools/run_playtest.sh <godot> [strategy] [out.log] [mission]
#
# `mission` is a MissionCatalog id (nerava, cinder, hallow). Omitted means
# whatever a fresh save has unlocked, which is Nerava.
#
# Runs headless: Input.action_press() and InputEventMouseMotion work without a
# display server, and the player's own input path is what consumes them.
#
# The filter is line-buffered on purpose. Block-buffered, a run in progress
# shows a 4 KB-stale window of its own log, so "where has it got to" is
# unanswerable while it matters most - which is exactly while it is running.
set -uo pipefail
GODOT="${1:?usage: run_playtest.sh <godot> [strategy] [out.log] [mission]}"
STRATEGY="${2:-cautious}"
OUT="${3:-ci-logs/playtest-$STRATEGY.log}"
MISSION="${4:-}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# An absolute --out is taken as given. Joining it to the project directory
# silently wrote /home/user/game/tmp/... for a caller who asked for /tmp/...,
# and then the log everyone was tailing never appeared.
case "$OUT" in
  /*) OUT_PATH="$OUT" ;;
  *)  OUT_PATH="$PROJECT_DIR/$OUT" ;;
esac
mkdir -p "$(dirname "$OUT_PATH")"
# One session at a time. Two of these at once fight over the ENet port and the
# loser reports "hosting did not reach the lobby", which reads exactly like a
# game defect and is not one.
# Match the ENGINE running the playtest scene, not the string "playtest.tscn"
# wherever it appears. `pgrep -f playtest.tscn` also matches any shell whose own
# command line mentions it - including the one asking - so the guard deadlocked
# against itself and refused three runs that had nothing to wait for.
running() { pgrep -f "Godot_v.*playtest\.tscn" >/dev/null 2>&1; }
for _ in 1 2 3 4 5 6 7 8 9 10; do
  running || break
  sleep 2
done
if running; then
  echo "another playtest is already running; refusing to start a second" >&2
  exit 2
fi
ARGS=("--strategy=$STRATEGY" "--out=$OUT_PATH")
[ -n "$MISSION" ] && ARGS+=("--mission=$MISSION")
"$GODOT" --headless --path "$PROJECT_DIR" res://tools/playtest.tscn -- \
  "${ARGS[@]}" 2>&1 \
  | grep --line-buffered -vE "ALSA lib|libpulse|snd_|audio drivers failed"
exit "${PIPESTATUS[0]}"
