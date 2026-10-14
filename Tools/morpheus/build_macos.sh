#!/usr/bin/env bash
# Build arm64 cruncher on Apple Silicon and install into Resources/Morpheus/bin/.
# Usage: ./Tools/morpheus/build_macos.sh [clone-dir]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CLONE="${1:-${TMPDIR:-/tmp}/verbamac-morpheus-src}"
REPO_URL="${MORPHEUS_REPO_URL:-https://github.com/perseids-tools/morpheus.git}"

if [[ "$(uname -s)" != Darwin ]]; then
  echo "This script must run on macOS (Apple Silicon)." >&2
  exit 1
fi

if [[ ! -d "$CLONE/.git" ]]; then
  mkdir -p "$(dirname "$CLONE")"
  git clone --depth 1 "$REPO_URL" "$CLONE"
fi

cd "$CLONE/src"
make clean
# clang 16+ treats K&R qsort comparators as errors — suppress.
CFLAGS='-std=gnu89 -Wno-return-type -Wno-implicit-function-declaration -Wno-error=incompatible-function-pointer-types' \
  make LOADLIBES='-ll'
make install
file ../bin/cruncher

"$ROOT/Tools/morpheus/install_cruncher.sh" "$CLONE/bin/cruncher"
echo "Done. Optional: ./Tools/morpheus/fetch_stemlib.sh"
