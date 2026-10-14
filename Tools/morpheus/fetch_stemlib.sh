#!/usr/bin/env bash
# Fetch Perseids Morpheus stemlib (Latin + Greek) into Resources/Morpheus/stemlib.
# Safe to run on Linux or macOS. Does NOT build or fetch an arm64 cruncher.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${ROOT}/Resources/Morpheus/stemlib"
REPO_URL="${MORPHEUS_REPO_URL:-https://github.com/perseids-tools/morpheus.git}"
REF="${MORPHEUS_REF:-master}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/verbamac-morpheus.XXXXXX")"

cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

echo "==> Cloning ${REPO_URL} @ ${REF} (sparse: stemlib)"
git clone --depth 1 --filter=blob:none --sparse --branch "$REF" "$REPO_URL" "$TMP/morpheus"
git -C "$TMP/morpheus" sparse-checkout set stemlib

echo "==> Installing into ${DEST}"
mkdir -p "$DEST"
rm -rf "${DEST}/Latin" "${DEST}/Greek"
cp -a "$TMP/morpheus/stemlib/Latin" "$DEST/"
cp -a "$TMP/morpheus/stemlib/Greek" "$DEST/"

# Drop the PLACEHOLDER once real trees exist
rm -f "${DEST}/PLACEHOLDER.txt"

du -sh "${DEST}/Latin" "${DEST}/Greek" || true
echo "==> Done. Pair with an arm64 cruncher in Resources/Morpheus/bin/ (build on Mac)."
echo "    Dev override: export MORPHLIB=\"${DEST}\""
