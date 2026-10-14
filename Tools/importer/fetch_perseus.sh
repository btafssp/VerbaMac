#!/usr/bin/env bash
# Download Perseus L&S / LSJ TEI from PerseusDL/lexica (CC BY-SA).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
CACHE="${ROOT}/data/cache"
mkdir -p "$CACHE/lsj"

BASE="https://raw.githubusercontent.com/PerseusDL/lexica/master/CTS_XML_TEI/perseus/pdllex"

usage() {
  cat <<USAGE
Usage: $0 [--latin] [--greek] [--all]
  --latin   Download L&S Unicode TEI (~77 MB): lat.ls.perseus-eng2.xml
  --greek   Download all LSJ parts eng1–eng27 (~250 MB total)
  --all     Both

Files land in Tools/importer/data/cache/ (gitignored).
Prefer eng2 for Latin (Unicode Greek inside entries).

Full import after fetch:
  .venv/bin/python import_lexica.py --lang lat \\
      --tei data/cache/lat.ls.perseus-eng2.xml --out out/lat.sqlite --check
  .venv/bin/python import_lexica.py --lang grc \\
      --tei data/cache/lsj --out out/grc.sqlite
USAGE
}

do_latin=0
do_greek=0
[[ $# -eq 0 ]] && { usage; exit 1; }
for arg in "$@"; do
  case "$arg" in
    --latin) do_latin=1 ;;
    --greek) do_greek=1 ;;
    --all) do_latin=1; do_greek=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown: $arg"; usage; exit 1 ;;
  esac
done

fetch() {
  local url="$1" dest="$2"
  if [[ -f "$dest" ]]; then
    echo "exists: $dest ($(wc -c <"$dest") bytes)"
    return 0
  fi
  echo "GET $url"
  curl -fL --retry 3 -o "$dest.partial" "$url"
  mv "$dest.partial" "$dest"
  echo "saved $dest ($(wc -c <"$dest") bytes)"
}

if [[ "$do_latin" -eq 1 ]]; then
  fetch "$BASE/lat/ls/lat.ls.perseus-eng2.xml" "$CACHE/lat.ls.perseus-eng2.xml"
fi

if [[ "$do_greek" -eq 1 ]]; then
  for i in $(seq 1 27); do
    fetch "$BASE/grc/lsj/grc.lsj.perseus-eng${i}.xml" "$CACHE/lsj/grc.lsj.perseus-eng${i}.xml"
  done
fi

echo "Done. Cache: $CACHE"
