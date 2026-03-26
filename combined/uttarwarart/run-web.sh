#!/usr/bin/env bash
# Host the portfolio from repo root. Kill this script (e.g. Ctrl+C) to stop the server.
# Builds data/art-index.json from output_defaults, then serves the site.

set -e
cd "$(dirname "$0")"

echo "Building art index from output_defaults..."
node scripts/build-art-index.js

PORT="${PORT:-8080}"
echo "Serving at http://localhost:$PORT (Ctrl+C to stop)"
if command -v npx &>/dev/null; then
  exec npx --yes serve -p "$PORT"
else
  exec python3 -m http.server "$PORT"
fi
