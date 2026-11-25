#!/usr/bin/env bash
# Phase 4 tests against a live server:
#   1. server/tests/test_server.mjs  (Node 22+: HTTP + WebSocket, 20 tests)
#   2. tests/online/*.gd             (the Godot client against the server)
#
# Start a server first, with the world boss shrunk so the defeat test is fast:
#   WB_RUNTIME_ENV=WB_BOSS_HP=300 NAKAMA_BIN=... WB_DB=... server/run_local.sh &
#   server/run_tests.sh
# Every test creates fresh accounts, so the suite can run repeatedly against
# the same database. WB_NAKAMA_URL / WB_NAKAMA_KEY override the defaults.
set -uo pipefail
cd "$(dirname "$0")/.."
export WB_NAKAMA_URL="${WB_NAKAMA_URL:-http://127.0.0.1:7350}"
export WB_NAKAMA_KEY="${WB_NAKAMA_KEY:-wb-dev-server-key}"
export WB_URL="$WB_NAKAMA_URL"
if ! curl -sf -o /dev/null "$WB_NAKAMA_URL/healthcheck"; then
  echo "No server at $WB_NAKAMA_URL (start one with server/run_local.sh)."
  exit 2
fi
STATUS=0
echo "== Server module tests (Node) =="
node server/tests/test_server.mjs || STATUS=1
echo ""
echo "== Godot client tests against the server =="
GODOT_BIN="${GODOT:-godot}"
LOG=$(mktemp)
"$GODOT_BIN" --headless --path . -s res://tests/test_runner.gd -- --filter=online/ 2>&1 | tee "$LOG"
[ "${PIPESTATUS[0]}" -eq 0 ] || STATUS=1
grep -qE "SCRIPT ERROR|Parse Error" "$LOG" && STATUS=1
rm -f "$LOG"
exit $STATUS
