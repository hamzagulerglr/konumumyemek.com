#!/bin/bash
# Browser-only restaurant panel. Does not touch the iPhone simulator.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${KONUMUM_WEB_PORT:-8765}"
cd "$ROOT/web"
export KONUMUM_WEB_PORT="$PORT"
exec python3 "$ROOT/web/server.py"
