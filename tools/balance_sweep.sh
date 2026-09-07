#!/usr/bin/env bash
# Runs the balance simulation across several seeds and summarises the spread.
#
# Two things are needed for a usable balance verdict.
#
# 1. --fixed-fps. Without it the game advances on wall-clock delta, so the step
#    size depends on machine load and the same build at the same seed can finish
#    "won with 59 lives" or "lost on wave 19". That is not noise to average out,
#    it is a broken measurement.
# 2. Several seeds. Even with a fixed timestep the spread across seeds is wide,
#    so a single campaign is not evidence about a build.
#
# Usage: tools/balance_sweep.sh [hero] [difficulty] [map] [seeds...]

set -uo pipefail
cd "$(dirname "$0")/.."

GODOT=${GODOT:-godot}
HERO=${1:-parrotx2}
DIFF=${2:-normal}
MAP=${3:-fort_feather}
shift 3 2>/dev/null || true
SEEDS=("$@")
if [ ${#SEEDS[@]} -eq 0 ]; then
  SEEDS=(1 2 3 4 5)
fi

wins=0
total=0
printf '%-6s %-8s %-6s %-7s %-7s %-9s %s\n' seed outcome wave lives leaks unspent towers
for s in "${SEEDS[@]}"; do
  line=$("$GODOT" --headless --fixed-fps 60 --path . -s tests/run_headless.gd -- \
      res://tests/balance_sim.gd 80000 "$HERO" "$DIFF" "$MAP" "$s" 2>/dev/null \
      | grep -E '^\[SIM\] (VERDICT|towers built)')
  verdict=$(echo "$line" | grep VERDICT)
  towers=$(echo "$line" | grep 'towers built' | grep -oE '[0-9]+$')
  outcome=$(echo "$verdict" | awk '{print $3}')
  wave=$(echo "$verdict" | grep -oE 'wave=[0-9]+/[0-9]+' | cut -d= -f2)
  lives=$(echo "$verdict" | grep -oE 'lives=[0-9]+/[0-9]+' | cut -d= -f2)
  leaks=$(echo "$verdict" | grep -oE 'leaks=[0-9]+' | cut -d= -f2)
  unspent=$(echo "$verdict" | grep -oE 'unspent=[0-9]+' | cut -d= -f2)
  printf '%-6s %-8s %-6s %-7s %-7s %-9s %s\n' \
      "$s" "${outcome:-ERROR}" "${wave:-?}" "${lives:-?}" "${leaks:-?}" "${unspent:-?}" "${towers:-?}"
  total=$((total + 1))
  [ "${outcome:-}" = "VICTORY" ] && wins=$((wins + 1))
done
echo "--"
echo "won $wins of $total"
