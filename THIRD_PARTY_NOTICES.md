# Third-party components and data

VerbaMac — Copyright © 2026 Brian T. Austin. Licensed under the GNU GPL v3.0.

VerbaMac's own source code is licensed under the GNU General Public License,
version 3 (see `LICENSE`). It bundles or uses the following third-party
components, each under its own license. Full license texts are in `ThirdParty/`.

## Lewis & Short (Latin) and Liddell–Scott–Jones (Greek) lexica

- Source: https://github.com/PerseusDL/lexica
- License: Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)
  — `ThirdParty/Perseus-lexica-license.md`
- Credit: Text provided under a CC BY-SA license by the Perseus Digital Library,
  Tufts University (http://www.perseus.tufts.edu), with funding from the
  National Endowment for the Humanities.
- The SQLite databases shipped with VerbaMac (`lat.sqlite`, `grc.sqlite`) are
  adapted from these texts. They include corrections made with reference to the
  Thesaurus Linguae Latinae. These adapted databases, including the
  corrections, are likewise shared under CC BY-SA 4.0.

## Morpheus morphological analyzer (cruncher + stem libraries)

- Source: https://github.com/perseids-tools/morpheus
- License: Mozilla Public License 2.0 — `ThirdParty/Morpheus-LICENSE.txt`
- Morpheus was originally developed by Gregory Crane and the Perseus Project;
  the bundled `cruncher` binary is built unmodified from the source above
  (see `Tools/morpheus/build_macos.sh`).

## Whitaker's WORDS

- Source: https://github.com/mk270/whitakers-words
- By Colonel William A. Whitaker (USAF, Retired), 1936–2010.
- License notice: "Permission is hereby freely given for any and all use of
  program and data." — `ThirdParty/WORDS-LICENCE.txt`
