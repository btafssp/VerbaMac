# VerbaMac

VerbaMac is a free, native macOS app for reading Latin and Greek. Type a word
form and it shows every possible morphological analysis (via Morpheus), with
the full Lewis & Short (Latin) or Liddell–Scott–Jones (Greek) dictionary
article for the lemma you select. It works entirely offline.

Requirements: Apple Silicon Mac, macOS 14 Sonoma or later.

## Download and install

### With Homebrew (recommended)

```sh
brew tap btafssp/verbamac
brew trust btafssp/verbamac   # newer Homebrew versions require trusting third-party taps
brew install --cask verbamac
```

Update later with `brew upgrade --cask verbamac`. The tap lives at [btafssp/homebrew-verbamac](https://github.com/btafssp/homebrew-verbamac). Because VerbaMac is not notarized, approve it once on first launch (System Settings › Privacy & Security › Open Anyway), or run `xattr -dr com.apple.quarantine /Applications/VerbaMac.app`.

### Manual download


1. Go to the [Releases](../../releases) page and download the latest
   `VerbaMac` zip.
2. Unzip it and drag **VerbaMac.app** into your Applications folder.
3. **First launch:** VerbaMac is free and not notarized by Apple, so macOS
   will block it the first time with a message that it cannot verify the
   developer.
   - Try to open VerbaMac once and click **Done** (or **OK**) on the warning.
   - Open **System Settings › Privacy & Security**, scroll down, and click
     **Open Anyway** next to the VerbaMac message. Confirm with your password.
   - From then on VerbaMac opens normally.

A Homebrew tap is planned.

## Building from source

You need Xcode 15 or later on an Apple Silicon Mac.

1. **Morpheus cruncher.** Build the arm64 `cruncher` and install it into
   `Resources/Morpheus/bin/`:

   ```bash
   ./Tools/morpheus/build_macos.sh
   ./Tools/morpheus/fetch_stemlib.sh   # if the stem libraries are missing
   ```

2. **Dictionary databases.** The `lat.sqlite` and `grc.sqlite` databases are
   too large for the repository. Either:
   - download them from the latest [Release](../../releases) and place them in
     `Resources/Lexicon/`, or
   - generate them from the Perseus TEI files with the importer (see
     [`Tools/importer/README.md`](Tools/importer/README.md)):

     ```bash
     cd Tools/importer
     python3 -m venv .venv
     .venv/bin/pip install -r requirements.txt
     ./fetch_perseus.sh
     .venv/bin/python import_lexica.py --lang lat --tei data/cache/lat.ls.perseus-eng2.xml --out out/lat.sqlite
     .venv/bin/python import_lexica.py --lang grc --tei data/cache/lsj/*.xml --out out/grc.sqlite
     cp out/*.sqlite ../../Resources/Lexicon/
     ```

     Note: databases generated this way lack the TLL-based corrections that
     are included in the Release databases.

3. Open `VerbaMac.xcodeproj` in Xcode and run the **VerbaMac** scheme.

## Licenses

- VerbaMac's source code: © 2026 Brian T. Austin, **GNU GPL v3.0** — see [`LICENSE`](LICENSE).
- Lewis & Short and LSJ texts: **CC BY-SA 4.0**, Perseus Digital Library,
  Tufts University, with funding from the NEH
  ([PerseusDL/lexica](https://github.com/PerseusDL/lexica)). The bundled
  databases, including their corrections, are shared under the same license.
- Morpheus: **Mozilla Public License 2.0**
  ([perseids-tools/morpheus](https://github.com/perseids-tools/morpheus)).
- Whitaker's WORDS: free-use notice by William A. Whitaker
  ([mk270/whitakers-words](https://github.com/mk270/whitakers-words)).
- Inspired by Verba, a Lewis & Short browser for Mac by Joshua Hayes (v1.1, 2010; no longer maintained).

Built with the help of Grok Bot 0.70.2.

Details and full texts: [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md) and
[`ThirdParty/`](ThirdParty/).

## Bug reports

Please report bugs and suggestions through
[GitHub Issues](../../issues). Include the word you searched, the language,
and what you expected to see.
