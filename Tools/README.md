# Tools

## Morpheus (`Tools/morpheus/`)

| Script / doc | Purpose |
|--------------|---------|
| `fetch_stemlib.sh` | Download `stemlib/Latin` + `Greek` from perseids-tools/morpheus → `Resources/Morpheus/stemlib/` |
| `install_cruncher.sh` | Copy a Mac-built `cruncher` into `Resources/Morpheus/bin/` |
| `build_linux_notes.md` | Linux ELF build for smoke tests only; **not** arm64 Mach-O |
| `sample_nl_output.txt` | Example Perseus `<NL>` lines |
| `check_sample_nl.py` | Lightweight shape check of the sample file |

See also `Resources/Morpheus/README.md`.

## Lexicon importer (`Tools/importer/`)

| Script / doc | Purpose |
|--------------|---------|
| `import_lexica.py` | TEI/sample → SQLite + zstd (`articles`, `zdicts`, FTS5) |
| `fetch_perseus.sh` | Download Perseus L&S / LSJ TEI into `data/cache/` |
| `requirements.txt` | `zstandard`, `lxml` |
| `data/samples/` | Real `entryFree` extracts: amo, custos, λόγος |
| `README.md` | Data URLs, train dicts, full import steps |

```bash
cd Tools/importer
python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
.venv/bin/python import_lexica.py --seed --no-dict \
  --out ../../Resources/Lexicon/seed.sqlite --check
```
