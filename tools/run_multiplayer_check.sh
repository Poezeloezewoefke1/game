#!/usr/bin/env bash
# Real multi-process multiplayer check for STARBOUND STATION.
#
# Launches one host and several client processes that talk over real ENet on
# loopback, then asserts on their structured NETCHECK output. This is the only
# check in the repository that exercises the CLIENT side of the protocol -
# everything in tests/integration runs host-side inside a single process.
#
#   usage: tools/run_multiplayer_check.sh <path-to-godot> [port] [clients]
#
# Exits non-zero if any probe reports FAIL, if a probe fails to finish, or if
# the total number of PASS lines is below what the configuration should produce.

set -uo pipefail

GODOT="${1:?usage: run_multiplayer_check.sh <godot-binary> [port] [clients]}"
PORT="${2:-7700}"
CLIENTS="${3:-2}"

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Hard ceiling per probe. A Godot process whose main scene fails to load does
# NOT exit on its own - it sits with an empty tree - so without this the script
# would block in `wait` until CI killed the whole job with no diagnosis.
PROBE_TIMEOUT="${PROBE_TIMEOUT:-240}"
LOG_DIR="${PROJECT_DIR}/ci-logs"
mkdir -p "$LOG_DIR"
rm -f "$LOG_DIR"/netcheck-*.log

# Sets LAST_PID rather than echoing it: command substitution would run this in
# a subshell, and the background job would then not be a child of this shell -
# `wait` would refuse it and the script would race ahead of the probes.
LAST_PID=""
run_probe() {
  local name="$1"; shift
  timeout --kill-after=10 "$PROBE_TIMEOUT" \
    "$GODOT" --headless --path "$PROJECT_DIR" res://tests/net_probe.tscn -- "$@" \
    > "$LOG_DIR/netcheck-$name.log" 2>&1 &
  LAST_PID=$!
}

# Pre-flight: a probe script that does not compile would otherwise present as a
# mysterious hang rather than a clear failure.
if ! "$GODOT" --headless --path "$PROJECT_DIR" --check-only \
     --script res://tests/net_probe.gd > "$LOG_DIR/netcheck-preflight.log" 2>&1; then
  if grep -q "Parse Error" "$LOG_DIR/netcheck-preflight.log"; then
    echo "RESULT: FAIL - tests/net_probe.gd does not parse:"
    grep -E "Parse Error|Compile Error" "$LOG_DIR/netcheck-preflight.log" | head -10
    exit 1
  fi
fi

echo "== multiplayer check: host + $CLIENTS client(s) on UDP $PORT =="

run_probe host --role=host "--port=$PORT" "--peers=$CLIENTS" --name=HostProbe
HOST_PID=$LAST_PID
# Let the listen socket come up before the clients dial in.
sleep 3

CLIENT_PIDS=()
for i in $(seq 0 $((CLIENTS - 1))); do
  run_probe "client$i" --role=client "--port=$PORT" \
    --address=127.0.0.1 "--name=Crew$i" "--slot=$i"
  CLIENT_PIDS+=("$LAST_PID")
  sleep 1
done

# At the player cap, add one more client that MUST be turned away with a clear
# message rather than silently dropped.
REJECT_PID=""
if [ "$CLIENTS" -ge 3 ]; then
  # Immediately: the host holds the lobby open for a fixed window after the
  # roster fills, so this lands while the session is FULL but not yet started.
  run_probe reject --role=reject "--port=$PORT" --address=127.0.0.1 --name=Overflow
  REJECT_PID=$LAST_PID
fi

FAILED=0
wait "$HOST_PID" || FAILED=1
for pid in "${CLIENT_PIDS[@]}"; do
  wait "$pid" || FAILED=1
done
if [ -n "$REJECT_PID" ]; then
  wait "$REJECT_PID" || FAILED=1
fi

echo
echo "---- probe output ----"
cat "$LOG_DIR"/netcheck-*.log | grep -E "^NETCHECK" || true
echo "----------------------"

PASSES=$(grep -hc "^NETCHECK PASS" "$LOG_DIR"/netcheck-*.log | paste -sd+ - | bc 2>/dev/null || echo 0)
FAILS=$(grep -h "^NETCHECK FAIL" "$LOG_DIR"/netcheck-*.log | wc -l | tr -d ' ')
DONE=$(grep -h "^NETCHECK DONE" "$LOG_DIR"/netcheck-*.log | wc -l | tr -d ' ')
EXPECTED_DONE=$((CLIENTS + 1))
if [ "$CLIENTS" -ge 3 ]; then
  EXPECTED_DONE=$((EXPECTED_DONE + 1))
fi

echo "passes=$PASSES fails=$FAILS finished=$DONE/$EXPECTED_DONE"

if [ "$FAILS" -ne 0 ]; then
  echo "RESULT: FAIL - $FAILS assertion(s) failed"
  exit 1
fi
if [ "$DONE" -ne "$EXPECTED_DONE" ]; then
  echo "RESULT: FAIL - only $DONE of $EXPECTED_DONE probes finished (a process hung or crashed)"
  exit 1
fi
if [ "$FAILED" -ne 0 ]; then
  echo "RESULT: FAIL - a probe exited non-zero"
  exit 1
fi
# A silent probe that reports nothing must not be mistaken for success.
MIN_PASSES=$((10 + CLIENTS * 12))
if [ "$PASSES" -lt "$MIN_PASSES" ]; then
  echo "RESULT: FAIL - only $PASSES passes, expected at least $MIN_PASSES"
  exit 1
fi

echo "RESULT: PASS - $PASSES assertions across $DONE processes"
