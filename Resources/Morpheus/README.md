# Bundled Morpheus layout

Ship these paths inside the app bundle (Xcode: copy `Resources/Morpheus` into the target’s Copy Bundle Resources, preserving structure):

```
Resources/Morpheus/
├── README.md          ← this file
├── bin/
│   └── cruncher       ← arm64 macOS Mach-O (NOT checked in; build on Mac)
└── stemlib/
    ├── Latin/         ← full tree from perseids-tools/morpheus
    └── Greek/
```

## What is NOT in this repo yet

| Artifact | Status |
|----------|--------|
| `bin/cruncher` (arm64) | **Must be built on an Apple Silicon Mac** (see below). This Linux workspace cannot produce a macOS arm64 Mach-O. |
| `stemlib/Latin`, `stemlib/Greek` | Fetch with `Tools/morpheus/fetch_stemlib.sh` (public GitHub data). Placeholders only until you run the script. |

## Build arm64 `cruncher` on Mac

Tested upstream recipe ([perseids-tools/morpheus](https://github.com/perseids-tools/morpheus), Apple M1 / Ventura):

```bash
git clone https://github.com/perseids-tools/morpheus.git
cd morpheus/src
make clean
CFLAGS='-std=gnu89 -Wno-return-type -Wno-implicit-function-declaration -Wno-error=incompatible-function-pointer-types' make LOADLIBES='-ll'
make install   # installs to ../bin/cruncher
file ../bin/cruncher   # expect: Mach-O 64-bit executable arm64
```

Requirements: Xcode Command Line Tools (`flex` / `lex`, `clang`, `make`).
On Apple clang 16+ (Xcode 16 / recent CLT), add `-Wno-error=incompatible-function-pointer-types`
(included above) — older K&R `qsort` comparators are errors by default.

Copy into VerbaMac:

```bash
cp bin/cruncher /path/to/VerbaMac/Resources/Morpheus/bin/cruncher
chmod +x /path/to/VerbaMac/Resources/Morpheus/bin/cruncher
```

Rebuild stemlibs only if you change stem sources (same `CFLAGS`):

```bash
cd stemlib/Greek && make clean
PATH="$PATH:../../bin" MORPHLIB='..' make && PATH="$PATH:../../bin" MORPHLIB='..' make
cd ../Latin && make clean
PATH="$PATH:../../bin" MORPHLIB='..' make && PATH="$PATH:../../bin" MORPHLIB='..' make
```

## Fetch stemlibs (Linux or Mac)

From the VerbaMac repo root:

```bash
./Tools/morpheus/fetch_stemlib.sh
```

This shallow-clones `perseids-tools/morpheus` and copies `stemlib/Latin` + `stemlib/Greek` into `Resources/Morpheus/stemlib/`.

## Dev overrides (no rebundle)

| Env var | Meaning |
|---------|---------|
| `VERBAMAC_MORPHEUS` | Absolute path to `cruncher` |
| `MORPHLIB` or `VERBAMAC_MORPHLIB` | Absolute path to directory containing `Latin/` and `Greek/` |

Example:

```bash
export VERBAMAC_MORPHEUS="$HOME/src/morpheus/bin/cruncher"
export MORPHLIB="$HOME/src/morpheus/stemlib"
open VerbaMac.xcodeproj
```

## Invocation (app)

- Latin: `cruncher -L -S` with the surface form on stdin (enclitics `-que/-ne/-ve` stripped first).
- Greek: Unicode → Beta Code, then `cruncher -S` (optional `-n` ignore accents).
- `MORPHLIB` is set to the resolved stemlib root.

## License

Morpheus data/code lineage: Perseus / Perseids / Alpheios / Alatius. Spec credit: **CC BY-SA 3.0** (offer modifications back). The `perseids-tools/morpheus` tree you build from also carries **MPL-2.0** — read that LICENSE before redistributing binaries.

## Cross-compile note

There is **no supported Linux → macOS arm64 cross-build** in-tree. Build `cruncher` natively on the Mac that will run VerbaMac. A Linux `cruncher` (x86_64/arm64 ELF) is useful only for format/smoke tests on this box — see `Tools/morpheus/build_linux_notes.md`.
