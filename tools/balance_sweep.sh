#!/usr/bin/env bash
# Runs the balance simulation across several seeds and summarises the spread.
#
# A single campaign is far too noisy to tune against -- back-to-back runs of the
# same build have finished anywhere between "won with 80 lives" and "lost on
# wave 23" -- so a balance verdict needs a distribution, not a sample.
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
  line=$("$GODOT" --headless --path . -s tests/run_headless.gd -- \
      res://tests/balance_sim.gd 60000 "$HERO" "$DIFF" "$MAP" "$s" 2>/dev/null \
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
