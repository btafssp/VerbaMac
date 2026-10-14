# Building Morpheus on Linux (format / smoke tests only)

**This does not produce the arm64 macOS `cruncher` VerbaMac ships.** Use it only to:

- Validate stemlib fetch
- Inspect Perseus `<NL>…</NL>` stdout for parser fixtures
- Smoke-test preprocessing / Beta Code offline

## Recipe (x86_64 or aarch64 Linux)

From [perseids-tools/morpheus](https://github.com/perseids-tools/morpheus):

```bash
sudo apt-get install -y build-essential flex   # or equivalent
git clone https://github.com/perseids-tools/morpheus.git
cd morpheus/src
make clean
CFLAGS='-std=gnu89 -fcommon' make
make install
# binary: ../bin/cruncher  (ELF for *this* host — not Mach-O)

export MORPHLIB="$(pwd)/../stemlib"
echo 'cactus' | ../bin/cruncher -S -L
echo 'a)/nqrwpos' | ../bin/cruncher -S
```

## macOS arm64 (required for the app)

See `Resources/Morpheus/README.md`. Must run on Apple Silicon with Xcode CLT.

Apple clang 16+ needs an extra flag (already in the README recipe):
`-Wno-error=incompatible-function-pointer-types`.

## Cross-compile Linux → macOS

**Not supported here.** Apple’s toolchain / SDK is required for a Mach-O arm64 binary. Do not expect `aarch64-linux-gnu-gcc` or similar to produce a runnable VerbaMac helper.

## Optional: Docker smoke test

```bash
docker pull perseidsproject/morpheus
docker run --rm perseidsproject/morpheus \
  bash -lc 'echo cactus | MORPHLIB=stemlib bin/cruncher -S -L'
```

Capture stdout for unit-test fixtures; still copy a **Mac-built** binary into `Resources/Morpheus/bin/` for the app.
