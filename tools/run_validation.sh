#!/usr/bin/env bash
# The full headless validation gate.
#
# Wraps the import pass and the test runner, and - importantly - FAILS on engine
# errors that the runner itself cannot see.
#
# Why that matters: GDScript cannot hook the engine's error stream, so a
# `SCRIPT ERROR` raised inside a test (a null dictionary access, a bad cast, an
# illegal RPC) is printed by the engine and the test suite still reports PASS.
# A real revive-race crash was found exactly this way, sitting inside an
# otherwise green run. The log is the only place that information exists, so the
# log is checked here.
#
#   usage: tools/run_validation.sh <path-to-godot>

set -uo pipefail

GODOT="${1:?usage: run_validation.sh <godot-binary>}"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="${PROJECT_DIR}/ci-logs"
mkdir -p "$LOG_DIR"

echo "== import =="
# The import pass also registers global class names. A newly added `class_name`
# is invisible to everything downstream until this has run.
"$GODOT" --headless --path "$PROJECT_DIR" --import > "$LOG_DIR/import.log" 2>&1
if grep -qE "SCRIPT ERROR|Parse Error|Compile Error" "$LOG_DIR/import.log"; then
  echo "RESULT: FAIL - the import pass reported script errors"
  grep -E "SCRIPT ERROR|Parse Error|Compile Error" "$LOG_DIR/import.log" | head -40
  exit 1
fi
echo "  ok"

echo "== validation and automated tests =="
"$GODOT" --headless --path "$PROJECT_DIR" res://tests/test_runner.tscn 2>&1 | tee "$LOG_DIR/tests.log"
RUNNER_STATUS=${PIPESTATUS[0]}

if [ "$RUNNER_STATUS" -ne 0 ]; then
  echo "RESULT: FAIL - the test runner exited $RUNNER_STATUS"
  exit 1
fi

# Engine-level errors the runner is blind to. `ERROR:` alone is too broad - the
# engine emits benign RID-leak notices at exit for objects a test allocated -
# so only genuinely actionable classes are matched.
ENGINE_ERRORS=$(grep -nE "SCRIPT ERROR|Parse Error|Compile Error|is not allowed on node|ERR_UNAUTHORIZED|Unable to send packet|Attempt to call RPC with unknown peer" \
  "$LOG_DIR/tests.log" || true)
if [ -n "$ENGINE_ERRORS" ]; then
  echo
  echo "RESULT: FAIL - the tests passed but the engine reported errors:"
  echo "$ENGINE_ERRORS" | head -40
  echo
  echo "These do not fail the runner on their own, which is exactly why they are"
  echo "checked here. Fix them or the suite is green over a real defect."
  exit 1
fi

echo
echo "RESULT: PASS - validation clean, no engine errors"
