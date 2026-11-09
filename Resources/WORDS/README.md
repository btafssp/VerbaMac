# Whitaker’s WORDS (Latin fallback)

VerbaMac calls this copy when Morpheus returns no Latin analyses.

- Binary: `bin/words` (mk270/whitakers-words, arm64)
- Dictionary data (`DICTFILE.GEN`, `STEMFILE.GEN`, `INDXFILE.GEN`, `INFLECTS.SEC`, `ADDONS.LAT`, `UNIQUES.LAT`) sit next to the binary because the app runs WORDS with that directory as the working directory.
- `bin/WORD.MOD` turns off `DO_FIXES` and `DO_TRICKS` so unknown forms are not given Whitaker-style suffix guesses (e.g. *mollites*). Genuine dictionary entries such as *memorial* still appear.

Rebuild notes: compile [mk270/whitakers-words](https://github.com/mk270/whitakers-words) with GNAT/gprbuild (`make all`), then copy `bin/words` and the generated data files listed above into `bin/`, keeping `WORD.MOD`.
