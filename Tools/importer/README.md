# Lexicon importer (L&S / LSJ → SQLite + zstd)

Build-time tool: Perseus TEI → compact HTML + plaintext + `lemma_norm`, then
**zstd with a trained dictionary per language** into the SPEC.md schema.

## Data URLs (PerseusDL/lexica, CC BY-SA)

| Lexicon | Path in repo | Notes / size |
|---------|--------------|--------------|
| **Lewis & Short** (Latin) | [`CTS_XML_TEI/perseus/pdllex/lat/ls/`](https://github.com/PerseusDL/lexica/tree/master/CTS_XML_TEI/perseus/pdllex/lat/ls) | Prefer **`lat.ls.perseus-eng2.xml`** (~77 MB, Unicode Greek inside). `eng1` keeps Greek in Beta Code. |
| **LSJ** (Greek) | [`CTS_XML_TEI/perseus/pdllex/grc/lsj/`](https://github.com/PerseusDL/lexica/tree/master/CTS_XML_TEI/perseus/pdllex/grc/lsj) | `grc.lsj.perseus-eng1.xml` … `eng27.xml` (~250 MB total). |

Raw base:

```
https://raw.githubusercontent.com/PerseusDL/lexica/master/CTS_XML_TEI/perseus/pdllex/
```

Credit (required by license):

> Text provided under a CC BY-SA license by Perseus Digital Library,
> http://www.perseus.tufts.edu, with funding from The National Endowment for the Humanities.
> Data accessed from https://github.com/PerseusDL/lexica/

## Setup (this Linux box or any machine)

```bash
cd Tools/importer
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Seed DB (three lemmas — already generated in-tree)

Samples under `data/samples/` are real Perseus `entryFree` extracts for
**amo**, **custos**, and **λόγος** (`lo/gos`).

```bash
cd Tools/importer
.venv/bin/python import_lexica.py --seed --no-dict \
  --out ../../Resources/Lexicon/seed.sqlite --check
# also refresh SPM copy:
cp ../../Resources/Lexicon/seed.sqlite ../../Sources/VerbaMac/Resources/Lexicon/seed.sqlite
```

`--no-dict` still **trains and stores** dicts in `zdicts`, but compresses article
frames **without** binding them to the dict so Apple `Compression.framework`
(`COMPRESSION_ZSTD`) can decompress on macOS. Full corpora should **omit**
`--no-dict` (dictionary compression — needs libzstd on the app side later).

## Fetch full corpora

```bash
./fetch_perseus.sh --latin          # ~77 MB
./fetch_perseus.sh --greek          # ~250 MB
./fetch_perseus.sh --all
```

Files land in `data/cache/` (gitignored).

## Full import

```bash
# Latin L&S → lat.sqlite
# Use --no-dict until the app links libzstd (Apple Compression cannot apply custom dicts).
.venv/bin/python import_lexica.py --lang lat \
  --tei data/cache/lat.ls.perseus-eng2.xml \
  --out out/lat.sqlite --no-dict --check

# Greek LSJ → grc.sqlite (directory of parts)
.venv/bin/python import_lexica.py --lang grc \
  --tei data/cache/lsj \
  --out out/grc.sqlite

# Combined DB with lang column
.venv/bin/python import_lexica.py --seed \
  --lang lat --tei data/cache/lat.ls.perseus-eng2.xml \
  --out out/lexica.sqlite
```

`--limit N` imports only the first N articles (smoke tests).

### Train zstd dictionaries

Handled inside `write_database()`:

1. Collect HTML samples per `lang`.
2. `zstandard.train_dictionary(dict_size, samples)` (default **32 KiB**).
3. Compress each `html` with that dict → `articles.html_zstd`.
4. Store raw dict bytes in `zdicts(lang, dict)`.
5. `VACUUM`; `page_size=8192`.

Override size: `--dict-size 65536`.

## Schema

See project `SPEC.md`. FTS5 on uncompressed `plain`.

## Bundled samples (no full download required)

| File | Source |
|------|--------|
| `data/samples/amo.entryFree.xml` | L&S `key="amo"` |
| `data/samples/custos.entryFree.xml` | L&S `key="custos"` |
| `data/samples/logos.entryFree.xml` | LSJ `key="lo/gos"` (large article) |

## App wiring

- Bundle / Application Support DB: `LexiconStore` opens SQLite read-only.
- Env override: `VERBAMAC_LEXICON_DB=/path/to/lexica.sqlite`
- Decompress: `ZstdCodec` (Compression.framework; dict path stubbed for libzstd).
- Seed HTML remains as fallback when DB missing or dict-zstd cannot be decoded.

## Gaps

- Full TEI→HTML is lossy (citations simplified); good enough for v1 reading pane.
- LSJ Beta Code in `<orth>` / `<foreign>` converted with a **subset** converter.
- Apple removed `COMPRESSION_ZSTD` from Compression.framework (macOS 27 / Xcode 27 SDK).
  VerbaMac `ZstdCodec` loads **libzstd** via `dlopen` (Homebrew `/opt/homebrew/lib/libzstd.dylib`).
  Full corpora: `--no-dict` is fine for no-dict frames; dict frames also work once libzstd is present.
- Huge DOCTYPE/entity dumps: importer strips DOCTYPE to a sibling `*.nodtd.xml` (can use disk).
