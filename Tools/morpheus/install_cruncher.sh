#!/usr/bin/env bash
# Copy a built cruncher into Resources/Morpheus/bin/.
# Usage: ./Tools/morpheus/install_cruncher.sh /path/to/morpheus/bin/cruncher
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
SRC="${1:?Usage: $0 /path/to/cruncher}"
DEST="${ROOT}/Resources/Morpheus/bin/cruncher"
mkdir -p "$(dirname "$DEST")"
cp -f "$SRC" "$DEST"
chmod +x "$DEST"
file "$DEST" || true
echo "Installed → $DEST"
echo "Tip: also run ./Tools/morpheus/fetch_stemlib.sh if stemlib is empty."
