# Project: VerbaMac (working title)

Native **SwiftUI** macOS app for Apple Silicon (M4). **Not Electron, not a web wrapper.** Offline-first. Target current macOS SDK.

## Purpose

Type or paste a Latin **or** Greek word form → morphological analyses → full lexicon article for the lemma.

Reference UI (copy this layout, not the stack):

- Latin parse + L&S: `https://d.iogen.es/parse?user=acad&dweb=1.011&popup=1&do=parse&lang=lat&q=custodes`
- Latin WORDS-only (fallback parser): `https://anastrophe.uchicago.edu/words?word=custodes`

Top pane: analyses. Bottom pane: dictionary article. Lemma in the parse list is selectable and drives the article.

## Features (v1)

1. Search field; Return runs parse.
2. Language: Latin | Greek | Both (autodetect if obvious).
3. Parser results: lemma, POS, full morphology; Latin quantity when Morpheus provides it.
4. Lexicon pane: full **Lewis & Short** (Latin) or **LSJ** (Greek) for the selected lemma.
5. Multiple analyses / homonyms listed; selecting one changes the article.
6. Offline after first data install.
7. History, back/forward, multiple windows.
8. macOS Services: “Look Up in VerbaMac” on selected text.
9. About box: credits and licenses (required).

Out of scope for v1: PHI/TLG corpora, TLL/OLD PDFs, DMLBS/DGE/Gaffiot, textbook hooks, frequency/collocations, English→Latin, Electron, wrapping Diogenes.app.

## Parsers

**Primary: Perseus Morpheus** (`cruncher`).

- Latin: `cruncher -L -S`
- Greek: `cruncher -S` and `-n` (ignore accents) as a user option
- Ship an **arm64** `cruncher` + `stemlib/Latin` and `stemlib/Greek`
- Sources: Perseids/PerseusDL/Alatius/Alpheios Morpheus (CC BY-SA 3.0; offer modifications back)
- Preprocess: strip Latin enclitics `-que` `-ne` `-ve`; normalize `u/v` and `i/j` for lookup keys; Greek Unicode NFC

**Fallback (Latin only): Whitaker’s WORDS**

- When Morpheus returns nothing
- Freely reusable data/code (mk270/whitakers-words and ports)
- Do **not** make the Ada console the UI
- WORDS glosses are secondary; L&S is the definition

No WORDS for Greek.

## Lexica

- Latin: Lewis & Short 1879, Perseus TEI/JSON (CC BY-SA). Credit: Perseus Digital Library, NEH.
- Greek: LSJ 1940, Perseus TEI (CC BY-SA). Same credit. Logeion corrections welcome if available.
- Build-time importer: TEI/JSON → compact HTML + plaintext + normalized lemma.
- Optional: Logeion URL button for the current lemma.

## Storage

SQLite, read-only in the app.

```sql
CREATE TABLE articles (
  id         INTEGER PRIMARY KEY,
  lemma      TEXT NOT NULL,
  lemma_norm TEXT NOT NULL,
  lang       TEXT NOT NULL CHECK (lang IN ('lat','grc')),
  html_zstd  BLOB NOT NULL,
  plain      TEXT
);
CREATE INDEX idx_norm ON articles(lang, lemma_norm);
CREATE VIRTUAL TABLE articles_fts USING fts5(lemma, plain, content='articles');
CREATE TABLE zdicts (lang TEXT PRIMARY KEY, dict BLOB NOT NULL);
```

- Compress article HTML with **zstd + a trained dictionary per language** (Apple Compression.framework, `COMPRESSION_ZSTD`). Do not gzip each row independently. Do not zip the whole `.db` as the runtime format.
- Train dicts on a sample of articles at import time; store in `zdicts`.
- FTS5 on uncompressed `plain`, not on the blob.
- `VACUUM`; page_size 8K or 16K.
- Ship DBs compressed for download; inflate once into Application Support. App binary should stay small (no Chromium).

Size goal: both lexica offline in a few hundred MB or less after HTML + dictionary-zstd. SwiftUI binary should be tiny compared with Diogenes (~250 MB Electron + ~475 MB data ≈ 730 MB `.app`).

## UI

SwiftUI, two-pane (split): analyses | article (WebKit or AttributedString HTML). Clean, readable, dictionary-like. Dark Mode. Gentium or a similar classical font for Greek/Latin. Keyboard: ⌘L focus search, Return parse, arrows through analyses.

## Architecture

- `Parser` protocol: Morpheus (Process or in-process if you wrap C) and WORDS.
- `LexiconStore`: SQLite + zstd decompress on the fly.
- Lemma join: Morpheus/WORDS lemma → `lemma_norm` → article. Small alias table for i/j, u/v, accents.
- All parsing and lookup on a background queue; UI never blocks.

## Legal (About box)

- L&S and LSJ text: Perseus, CC BY-SA; credit Perseus + NEH.
- Morpheus: Perseus/Perseids, CC BY-SA 3.0.
- WORDS: Whitaker; freely reusable; link mk270.github.io/whitakers-words.
- App code: pick MIT or GPL-3 and state it.

## Deliverables

1. Xcode project, arm64, SwiftUI.
2. Python or Swift importer: Perseus data → `lat.sqlite` / `grc.sqlite` (or one DB with `lang`).
3. README: data download URLs, how to build stemlibs, how to train zstd dicts, how to run on Apple Silicon.
4. Seed data so the UI runs with a handful of entries (`custos`, `amo`, `λόγος`) before full import.

Start with the SwiftUI shell + fake parser + seed L&S row for `custos`, then wire Morpheus, then the importer.
