#!/bin/bash
# Keep the browser panel alive. NEVER xcodebuild / simctl / Lumen.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${KONUMUM_WEB_PORT:-8765}"
LOG="$ROOT/web/data/keep.log"
mkdir -p "$ROOT/web/data"
echo "$(date '+%F %T') keep-alive start" >>"$LOG"
while true; do
  if ! curl -sf "http://127.0.0.1:${PORT}/api/health" >/dev/null; then
    echo "$(date '+%F %T') web down — restart server.py" >>"$LOG"
    python3 "$ROOT/web/server.py" >>"$LOG" 2>&1 &
    sleep 2
  fi
  sleep 20
done
