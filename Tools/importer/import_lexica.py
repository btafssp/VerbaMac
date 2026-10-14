#!/usr/bin/env python3
"""
VerbaMac lexicon importer — Perseus L&S (Latin) / LSJ (Greek) TEI → SQLite.

Examples:
  # Seed DB from bundled sample entryFree fragments (custos, amo, λόγος):
  python import_lexica.py --seed --out ../../Resources/Lexicon/seed.sqlite

  # Full Latin L&S (after fetch):
  python import_lexica.py --lang lat --tei data/cache/lat.ls.perseus-eng2.xml \\
      --out out/lat.sqlite

  # Full Greek LSJ (many files):
  python import_lexica.py --lang grc --tei data/cache/lsj/*.xml --out out/grc.sqlite

  # Combined:
  python import_lexica.py --seed --tei data/cache/lat.ls.perseus-eng2.xml \\
      --lang lat --out out/lexica.sqlite
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from verbamac_import.dbwrite import lookup, write_database
from verbamac_import.tei_parse import Article, finalize_xrefs, iter_entries_from_file, parse_fragment_file


SAMPLES = ROOT / "data" / "samples"


def load_seed_samples() -> list[Article]:
    mapping = [
        (SAMPLES / "amo.entryFree.xml", "lat"),
        (SAMPLES / "custos.entryFree.xml", "lat"),
        (SAMPLES / "logos.entryFree.xml", "grc"),
    ]
    arts: list[Article] = []
    for path, lang in mapping:
        if not path.exists():
            raise SystemExit(f"Missing sample {path}; re-fetch or restore samples/")
        arts.extend(parse_fragment_file(str(path), lang_hint=lang))
    return arts


def load_tei_paths(paths: list[Path], lang: str | None) -> list[Article]:
    arts: list[Article] = []
    for p in paths:
        print(f"  parsing {p} …", flush=True)
        # Prefer streaming for large files
        size = p.stat().st_size
        if size < 2_000_000 and p.read_text(encoding="utf-8", errors="replace").lstrip().startswith(
            "<entryFree"
        ):
            arts.extend(parse_fragment_file(str(p), lang_hint=lang))
        else:
            # Strip DOCTYPE via a filter if needed — write sanitized stream for huge files
            sanitized = _ensure_no_doctype(p)
            n_before = len(arts)
            for art in iter_entries_from_file(str(sanitized), lang_hint=lang):
                arts.append(art)
                if (len(arts) - n_before) % 5000 == 0 and len(arts) > n_before:
                    print(f"    … {len(arts) - n_before} entries", flush=True)
            print(f"    → {len(arts) - n_before} entries from {p.name}", flush=True)
            if sanitized != p:
                sanitized.unlink(missing_ok=True)
    return arts


def _ensure_no_doctype(path: Path) -> Path:
    """If file has DOCTYPE / entity refs that break ElementTree, write a cleaned temp copy.

    For multi-hundred-MB files we stream-copy while dropping the DOCTYPE line only.
    """
    # Peek first 8K
    head = path.read_bytes()[:8192]
    if b"<!DOCTYPE" not in head.upper() and b"<!doctype" not in head:
        return path
    out = path.with_suffix(path.suffix + ".nodtd.xml")
    if out.exists() and out.stat().st_mtime >= path.stat().st_mtime:
        return out
    print(f"  stripping DOCTYPE → {out.name}", flush=True)
    import re

    with path.open("rb") as inf, out.open("wb") as outf:
        data = inf.read()
        # Remove DOCTYPE declaration (may be multiline with internal subset)
        text = data.decode("utf-8", errors="replace")
        text = re.sub(r"<!DOCTYPE[\s\S]*?\[[\s\S]*?\]\s*>", "", text, count=1, flags=re.I)
        text = re.sub(r"<!DOCTYPE[^>]*>", "", text, count=1, flags=re.I)
        outf.write(text.encode("utf-8"))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", action="store_true", help="Include bundled amo/custos/logos samples")
    ap.add_argument("--tei", nargs="*", type=Path, default=[], help="TEI XML file(s) or globs")
    ap.add_argument("--lang", choices=["lat", "grc"], default=None, help="Force language for --tei")
    ap.add_argument(
        "--out",
        type=Path,
        default=ROOT / "out" / "lexica.sqlite",
        help="Output SQLite path",
    )
    ap.add_argument("--dict-size", type=int, default=32 * 1024, help="zstd dict size bytes")
    ap.add_argument("--limit", type=int, default=0, help="Max articles (0=all); useful for smoke tests")
    ap.add_argument("--check", action="store_true", help="After write, lookup seed lemmas")
    ap.add_argument(
        "--no-dict",
        action="store_true",
        help="Compress HTML without a trained dict (Apple Compression.framework can decode; "
             "still trains/stores dict in zdicts for schema). Prefer dict compression for full corpora.",
    )
    args = ap.parse_args()

    # Expand globs
    tei_files: list[Path] = []
    for t in args.tei:
        if any(ch in str(t) for ch in "*?["):
            tei_files.extend(sorted(Path().glob(str(t))))
        elif t.is_dir():
            tei_files.extend(sorted(t.glob("*.xml")))
        else:
            tei_files.append(t)

    articles: list[Article] = []
    if args.seed:
        print("Loading seed samples…")
        articles.extend(load_seed_samples())

    if tei_files:
        print(f"Loading {len(tei_files)} TEI file(s)…")
        articles.extend(load_tei_paths(tei_files, args.lang))

    if not articles:
        print("No articles. Pass --seed and/or --tei PATH", file=sys.stderr)
        return 2

    # Dedupe by (lang, lemma_norm) keeping first
    seen: set[tuple[str, str]] = set()
    unique: list[Article] = []
    for a in articles:
        # LSJ homographs (λύω? a)/atos1, a)/atos2) share lemma_norm — keep all, keyed by TEI key.
        # L&S homographs too (abdico1 ab-dĭco / abdico2 ab-dīco): TEI keys are unique.
        k = (a.lang, a.key or a.lemma_norm)
        if k in seen:
            continue
        seen.add(k)
        unique.append(a)
    articles = unique

    if args.limit and args.limit > 0:
        articles = articles[: args.limit]

    xs = finalize_xrefs(articles)
    if any(xs.values()):
        print(f"Cross-refs: {xs}")
    print(f"Writing {len(articles)} articles → {args.out}")
    stats = write_database(args.out, articles, dict_size=args.dict_size, use_dict=not args.no_dict)
    print(
        f"Done: {stats['articles']} rows "
        f"(lat={stats['lat']} grc={stats['grc']}) "
        f"size={stats['bytes']} bytes dicts={stats['dicts']}"
    )

    if args.check or args.seed:
        print("Smoke lookups:")
        checks = [("lat", "custos"), ("lat", "amo"), ("grc", "λογος")]
        # Only require lemmas for languages actually present in the DB
        import sqlite3
        langs = {r[0] for r in sqlite3.connect(str(args.out)).execute(
            "SELECT DISTINCT lang FROM articles"
        )}
        failed = False
        for lang, norm in checks:
            if lang not in langs:
                print(f"  SKIP {lang}:{norm} (lang not in DB)")
                continue
            hit = lookup(args.out, lang, norm)
            if hit:
                lemma, html, plain = hit
                print(f"  OK {lang}:{norm} → {lemma!r} html={len(html)}B plain={plain[:60]!r}…")
            else:
                print(f"  MISS {lang}:{norm}")
                failed = True
        if failed:
            return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
