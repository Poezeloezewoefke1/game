#!/usr/bin/env bash
# Repository structure and hygiene check.
#
# Fails fast on the things that break a build or leak something private, before
# the (much slower) Godot validation runs. Safe to run locally:
#   tools/check_structure.sh

set -uo pipefail
cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAILURES=0
fail() { echo "  FAIL  $*"; FAILURES=$((FAILURES + 1)); }
ok()   { echo "  ok    $*"; }

echo "== required directories =="
for d in assets docs resources scenes scripts tests .github/workflows .github/ISSUE_TEMPLATE tools; do
  if [ -d "$d" ]; then ok "$d"; else fail "missing directory: $d"; fi
done

echo "== required files =="
for f in project.godot export_presets.cfg main.tscn main.gd .gitignore LICENSE README.md CHANGELOG.md \
         tests/run_tests.gd tests/test_runner.tscn \
         tools/run_validation.sh tools/run_multiplayer_check.sh tools/check_structure.sh \
         .github/PULL_REQUEST_TEMPLATE.md \
         .github/ISSUE_TEMPLATE/bug_report.md .github/ISSUE_TEMPLATE/task.md \
         .github/workflows/validate.yml .github/workflows/build-windows.yml \
         docs/ARCHITECTURE.md docs/NETWORK_RULES.md docs/TECH_STACK.md docs/QA_REPORT.md \
         docs/TEST_CHECKLIST.md docs/KNOWN_LIMITATIONS.md docs/REQUIREMENTS_TRACEABILITY.md \
         docs/BUILD_MANIFEST.md docs/RELEASE_CHECKLIST.md docs/REPOSITORY_SETUP.md; do
  if [ -f "$f" ]; then ok "$f"; else fail "missing file: $f"; fi
done

echo "== the engine version must be pinned in exactly one place =="
PINNED=$(grep -oE '^GODOT_VERSION: *"?[0-9.]+-stable"?' .github/workflows/validate.yml 2>/dev/null | head -1 || true)
if [ -z "$PINNED" ]; then
  # The pin lives under `env:` and is indented.
  PINNED=$(grep -oE 'GODOT_VERSION: *"?[0-9]+\.[0-9]+(\.[0-9]+)?-stable"?' .github/workflows/validate.yml | head -1 || true)
fi
if [ -n "$PINNED" ]; then ok "validate.yml pins $PINNED"; else fail "validate.yml does not pin GODOT_VERSION"; fi

BUILD_PIN=$(grep -oE 'GODOT_VERSION: *"?[0-9]+\.[0-9]+(\.[0-9]+)?-stable"?' .github/workflows/build-windows.yml | head -1 || true)
if [ -n "$PINNED" ] && [ "$PINNED" = "$BUILD_PIN" ]; then
  ok "build-windows.yml pins the same version"
else
  # Two empty pins are not agreement - that is how a missing pin sneaks through.
  fail "workflow version pins missing or disagree: '$PINNED' vs '$BUILD_PIN'"
fi

echo "== no build output or secrets may be tracked =="
TRACKED_BAD=$(git ls-files 2>/dev/null | grep -E '\.(exe|pck|zip|dll|so|dylib)$|^build/|^builds/|^export/|^exports/|^\.godot/|^ci-logs/' || true)
if [ -z "$TRACKED_BAD" ]; then ok "no binaries or build output tracked"; else fail "tracked build output:"$'\n'"$TRACKED_BAD"; fi

# A conservative sweep. It must not fire on the words themselves appearing in
# documentation, so it looks for assignment-shaped secrets only.
SECRETS=$(git ls-files 2>/dev/null | grep -vE '^(docs/|tools/check_structure\.sh|\.github/)' | \
  xargs grep -InE '(api[_-]?key|secret|password|token)[[:space:]]*[:=][[:space:]]*"[^"]{8,}"' 2>/dev/null || true)
if [ -z "$SECRETS" ]; then ok "no assignment-shaped secrets"; else fail "possible secret:"$'\n'"$SECRETS"; fi

echo "== gitignore must cover generated output =="
for pat in ".godot/" "*.exe" "*.pck" "build/" "ci-logs/"; do
  if grep -qxF "$pat" .gitignore; then ok ".gitignore covers $pat"; else fail ".gitignore is missing $pat"; fi
done

echo "== script naming convention (snake_case) =="
BAD_NAMES=$(git ls-files 'scripts/*.gd' 'scenes/*.tscn' 'tests/*.gd' 2>/dev/null | \
  xargs -n1 basename 2>/dev/null | grep -vE '^[a-z0-9_]+\.(gd|tscn)$' || true)
if [ -z "$BAD_NAMES" ]; then ok "all script and scene files are snake_case"; else fail "non-snake_case:"$'\n'"$BAD_NAMES"; fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "RESULT: PASS - structure check clean"
  exit 0
fi
echo "RESULT: FAIL - $FAILURES problem(s)"
exit 1
