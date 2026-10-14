"""Write SPEC.md SQLite schema with zstd blobs + FTS5."""

from __future__ import annotations

import sqlite3
from pathlib import Path
from typing import Iterable, Optional

from .tei_parse import Article
from . import zstdutil


SCHEMA = """
PRAGMA journal_mode = OFF;
PRAGMA synchronous = OFF;
PRAGMA page_size = 8192;
PRAGMA encoding = 'UTF-8';

CREATE TABLE articles (
  id INTEGER PRIMARY KEY,
  lemma TEXT NOT NULL,
  lemma_norm TEXT NOT NULL,
  lang TEXT NOT NULL CHECK (lang IN ('lat','grc')),
  html_zstd BLOB NOT NULL,
  plain TEXT
);
CREATE INDEX idx_norm ON articles(lang, lemma_norm);
CREATE VIRTUAL TABLE articles_fts USING fts5(lemma, plain, content='articles');
CREATE TABLE zdicts (lang TEXT PRIMARY KEY, dict BLOB NOT NULL);
"""


def write_database(
    out_path: Path,
    articles: Iterable[Article],
    *,
    dict_size: int = zstdutil.DEFAULT_DICT_SIZE,
    vacuum: bool = True,
    use_dict: bool = True,
) -> dict:
    articles = list(articles)
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    if out_path.exists():
        out_path.unlink()

    # Train dicts per language on HTML samples (subsample large corpora)
    by_lang: dict[str, list[Article]] = {"lat": [], "grc": []}
    for a in articles:
        by_lang.setdefault(a.lang, []).append(a)

    dicts: dict[str, bytes] = {}
    max_train = 2048  # enough for a 32 KiB dict; avoids duplicating full corpus in RAM
    for lang, arts in by_lang.items():
        if not arts:
            continue
        step = max(1, len(arts) // max_train)
        train_arts = arts[::step][:max_train]
        samples = [a.html.encode("utf-8") for a in train_arts]
        dicts[lang] = zstdutil.train_dictionary(samples, dict_size=dict_size)

    conn = sqlite3.connect(str(out_path))
    try:
        conn.executescript(SCHEMA)
        for lang, d in dicts.items():
            conn.execute("INSERT INTO zdicts(lang, dict) VALUES (?, ?)", (lang, d))

        rows = []
        for a in articles:
            dbytes = (dicts.get(a.lang) or None) if use_dict else None
            blob = zstdutil.compress(a.html, dbytes)
            # roundtrip check first few
            rows.append((a.lemma, a.lemma_norm, a.lang, blob, a.plain))

        conn.executemany(
            "INSERT INTO articles(lemma, lemma_norm, lang, html_zstd, plain) VALUES (?,?,?,?,?)",
            rows,
        )
        # FTS content table sync
        conn.execute(
            "INSERT INTO articles_fts(rowid, lemma, plain) "
            "SELECT id, lemma, plain FROM articles"
        )
        conn.commit()

        # Verify roundtrip for all (small DBs) / sample
        cur = conn.execute("SELECT id, lang, html_zstd FROM articles")
        try:
            for i, (aid, lang, blob) in enumerate(cur):
                if i > 50 and len(articles) > 100:
                    break
                dbytes = (dicts.get(lang) or None) if use_dict else None
                text = zstdutil.decompress(blob, dbytes)
                assert text.startswith("<article"), f"bad decompress id={aid}"
        finally:
            cur.close()

        if vacuum:
            conn.execute("VACUUM")
            conn.commit()
    finally:
        conn.close()

    # Re-open to set page_size permanently: page_size must be set before tables;
    # we set it in SCHEMA before CREATE. VACUUM already applied.
    size = out_path.stat().st_size
    return {
        "path": str(out_path),
        "articles": len(articles),
        "lat": len(by_lang.get("lat", [])),
        "grc": len(by_lang.get("grc", [])),
        "bytes": size,
        "dicts": {k: len(v) for k, v in dicts.items()},
    }


def lookup(db_path: Path, lang: str, lemma_norm: str) -> Optional[tuple[str, str, str]]:
    """Return (lemma, html, plain) or None — for smoke tests."""
    conn = sqlite3.connect(str(db_path))
    try:
        row = conn.execute(
            "SELECT lemma, html_zstd, plain, lang FROM articles WHERE lang=? AND lemma_norm=? LIMIT 1",
            (lang, lemma_norm),
        ).fetchone()
        if not row:
            return None
        lemma, blob, plain, lang = row
        d = conn.execute("SELECT dict FROM zdicts WHERE lang=?", (lang,)).fetchone()
        dict_bytes = d[0] if d else None
        try:
            html = zstdutil.decompress(blob, dict_bytes)
        except Exception:
            # Frames written with --no-dict (Apple Compression.framework path)
            html = zstdutil.decompress(blob, None)
        return lemma, html, plain or ""
    finally:
        conn.close()
