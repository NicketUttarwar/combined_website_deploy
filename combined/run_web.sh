#!/usr/bin/env bash
# Serve the combined site: personal pages at / and the Uttarwar Art portfolio at /uttarwarart/
# Builds uttarwarart/data/art-index.json from output_defaults, then starts a static server.

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

PORT="${PORT:-8080}"
URL="http://127.0.0.1:${PORT}"

echo "Combined site root: $ROOT"
echo "Serving at $URL  (personal: $URL/  ·  art portfolio: $URL/uttarwarart/)"
echo "Press Ctrl+C to stop."
echo ""

if command -v open >/dev/null 2>&1; then
  (sleep 0.5 && open "$URL") &
elif command -v xdg-open >/dev/null 2>&1; then
  (sleep 0.5 && xdg-open "$URL") &
fi

exec python3 -m http.server "$PORT" --bind 127.0.0.1
