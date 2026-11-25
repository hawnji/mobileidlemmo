#!/usr/bin/env bash
# Starts a local Nakama for development and tests, using the module in
# server/nakama/modules. Needs a running PostgreSQL 12+ and the Nakama binary
# (https://github.com/heroiclabs/nakama/releases, tested with 3.22.0).
#
#   NAKAMA_BIN=/path/to/nakama \
#   WB_DB="postgres:password@127.0.0.1:5432/nakama" server/run_local.sh
#
# The HTTP key and server key below are development values. Production uses
# docker-compose.yml with real secrets from the environment.
set -euo pipefail
cd "$(dirname "$0")/.."
NAKAMA_BIN="${NAKAMA_BIN:-nakama}"
WB_DB="${WB_DB:-postgres:localdb@127.0.0.1:5432/nakama}"
DATA_DIR="${WB_NAKAMA_DATA:-/tmp/worldbound-nakama}"
python3 tools/build_server_module.py
mkdir -p "$DATA_DIR"
"$NAKAMA_BIN" migrate up --database.address "$WB_DB"
exec "$NAKAMA_BIN" --name worldbound-dev --database.address "$WB_DB" \
  --runtime.path "$PWD/server/nakama/modules" --data_dir "$DATA_DIR" \
  --runtime.http_key "${WB_HTTP_KEY:-wb-dev-http-key}" --socket.server_key "${WB_SERVER_KEY:-wb-dev-server-key}" \
  --session.token_expiry_sec 86400 --logger.level INFO ${WB_RUNTIME_ENV:+--runtime.env "$WB_RUNTIME_ENV"}
