#!/usr/bin/env bash
# Serve this folder as a static site on http://127.0.0.1:<port> (default 8080).
# Optional art index build for uttarwarart/ when Node is available.
#
# Usage:
#   ./run_web.sh           # PORT=8080
#   ./run_web.sh 9000      # port 9000
#   PORT=3000 ./run_web.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

ART_DIR="$ROOT/uttarwarart"
BUILD_SCRIPT="$ART_DIR/scripts/build-art-index.js"
if [[ -f "$BUILD_SCRIPT" ]] && command -v node &>/dev/null; then
  echo "Building art index..."
  (cd "$ART_DIR" && node scripts/build-art-index.js)
else
  echo "Skipping art index build (no build script or node not found)." >&2
fi

if [[ -n "${1:-}" ]]; then
  PORT="$1"
elif [[ -n "${PORT:-}" ]]; then
  PORT="$PORT"
else
  PORT=8080
fi

URL="http://127.0.0.1:${PORT}"

echo "Site root: $ROOT"
echo "Serving at $URL"
echo "Press Ctrl+C to stop."
echo ""

if command -v open >/dev/null 2>&1; then
  (sleep 0.5 && open "$URL") &
elif command -v xdg-open >/dev/null 2>&1; then
  (sleep 0.5 && xdg-open "$URL") &
fi

exec python3 -m http.server "$PORT" --bind 127.0.0.1 --directory "$ROOT"
