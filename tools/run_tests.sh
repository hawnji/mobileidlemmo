#!/usr/bin/env bash
# Runs the Worldbound test suite headless and fails on test failures OR on any
# script/engine error printed during the run.
#   tools/run_tests.sh [--filter=name]
# Uses $GODOT if set, otherwise `godot` from PATH.
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT_BIN="${GODOT:-godot}"
# Make sure the global class cache exists (first run / fresh clone).
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  "$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true
fi
LOG=$(mktemp)
"$GODOT_BIN" --headless --path . -s res://tests/test_runner.gd -- "$@" 2>&1 | tee "$LOG"
STATUS=${PIPESTATUS[0]}
# Boot the real game scene headless for a few seconds (scenes, UI, autoload).
if [ "$#" -eq 0 ]; then
  echo ""
  echo "Scene smoke test (Main.tscn, headless):"
  "$GODOT_BIN" --headless --path . -- --smoke-test 2>&1 | tee -a "$LOG" | grep -E "SMOKE|ERROR" || true
  grep -q "SMOKE TEST PASSED" "$LOG" || STATUS=1
fi
if grep -qE "SCRIPT ERROR|Parse Error|^ERROR:" "$LOG"; then
  echo ""
  echo "Engine/script errors were printed during the test run (see above)."
  STATUS=1
fi
rm -f "$LOG"
exit $STATUS
