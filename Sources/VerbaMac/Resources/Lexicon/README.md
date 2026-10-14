# Lexicon SQLite

  Rebuild: see `Tools/importer/README.md` (`--seed --no-dict`).
- `lat.sqlite` — full Lewis & Short (51,645 articles incl. homographs abdico1/abdico2; derivative `<orth>` forms inside articles kept) from Perseus
  `lat.ls.perseus-eng2.xml`. Compressed with zstd **without** trained-dict frames
  so Apple `Compression.framework` can decode (`--no-dict`).
  Rebuild:
  ```bash
  cd Tools/importer
  ./fetch_perseus.sh --latin
  .venv/bin/python import_lexica.py --lang lat \
    --tei data/cache/lat.ls.perseus-eng2.xml \
    --out out/lat.sqlite --no-dict --check
  cp out/lat.sqlite ../../Resources/Lexicon/lat.sqlite
  cp out/lat.sqlite ../../Sources/VerbaMac/Resources/Lexicon/lat.sqlite
  ```
- `grc.sqlite` — full LSJ (Liddell–Scott–Jones), **116,497 articles** from Perseus
  `grc.lsj.perseus-eng1–27.xml` (PerseusDL canonical-pdlrefwk). ~151 MB (152870912 bytes),
  zstd per row `--no-dict`; ships in the app bundle. LSJ length marks (ᾱ, ᾰ) kept as imported. Greek Beta Code is converted wherever TEI `lang="greek"` scopes it (incl. later `<orth>`, `<gen>`, `<etym>`); `<ref>` cross-refs become `<a class="xref" href="verba-xref:grc?l=…">` links; senses carry `id="sec-A.II.3"` anchors and a following section label ("v. εἴδω B.") adds `&s=B`. Second pass (`finalize_xrefs`): targets with no LSJ headword render as plain Greek (`span.xref-plain`); capital-marked targets whose headwords are all lowercase are shown lowercase (εἴδω), capitalized headwords keep the capital (Ἥφαιστος).
  Rebuild:
  ```bash
  cd Tools/importer
  ./fetch_perseus.sh --greek
  .venv/bin/python import_lexica.py --lang grc --tei data/cache/lsj \
    --out out/grc.sqlite --no-dict --check
  cp out/grc.sqlite ../../Resources/Lexicon/grc.sqlite
  cp out/grc.sqlite ../../Sources/VerbaMac/Resources/Lexicon/grc.sqlite
  ```
