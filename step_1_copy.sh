#!/usr/bin/env bash
set -euo pipefail

# Step 1: sync ../combined_personal_art_website/combined into ./combined (this repo).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${SCRIPT_DIR}/../combined_personal_art_website/combined"

if [[ ! -d "$SRC" ]]; then
  echo "copy.sh: source directory not found: $SRC" >&2
  exit 1
fi

cd "$SCRIPT_DIR"
rm -rf combined
cp -a "$SRC" ./combined

echo "copy.sh: copied to $SCRIPT_DIR/combined"
