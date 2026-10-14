# L&S → TLL display corrections (VerbaMac)

User decision 2026-10-13: the TLL is authoritative for these L&S source oddities.
Applied at display time in `LatinQuantity.tllCorrections` (headwords, analyses labels,
article heads and bodies). `lat.sqlite` is unchanged; search keys are unaffected.

| L&S source        | Displayed (TLL)  | Note |
|-------------------|------------------|------|
| consú^ētē         | cōnsuētē         | **TLL-confirmed** cōnsuētē (cōnsuēsco) |
| dēstrictárĭum     | dēstrictārium    | acute where macron belongs |
| augùrālis         | augurālis        | grave in source |
| augùrātĭo         | augurātio        | grave in source |
| circum-tuèŏr      | circum-tueor     | TLL circumtueor, stem unmarked |
| Ĕrўthēa "or -_ia" | "or -ia"         | not in TLL; stray `_` dropped only |

## Round 2 (2026-10-13): accent-for-quantity slips

The TLL site (tll.degruyter.com) is a JS app whose search returned no headings to a
headless fetch, so these were checked against L&S's own paradigms and Latin grammar,
not a live TLL heading.

| L&S source            | Displayed         | Where | Basis |
|-----------------------|-------------------|-------|-------|
| abscído               | abscīdo           | ab-cīdo | **TLL-confirmed** abscīdo |
| ìtúm                  | ĭtum              | cŭbo (ŭi, ĭtum) | **TLL-confirmed** (cubitum) |
| ìtum                  | ĭtum              | per-dŏlĕo; ē-lĭcĭo (lĭcĭtum) | short ĭ, as L&S elsewhere |
| féra                  | fĕra              | multĭ-fer | **TLL-confirmed** (multifer) |
| ullà / nullà          | ullā / nullā      | vărĭātĭo (Liv. 24, 9, 3); conscĭentĭa | ablative fem. |

Left unchanged:
- tineà (trĭ-cuspis) — English gloss ("three-tined"), not Latin.
- bála (vălĕo) — Sanskrit.  feó (pĕcus) — Anglo-Saxon.

## Round 3 (2026-10-13): TLL-confirmed by the user

| L&S source  | Displayed  | Basis |
|-------------|------------|-------|
| nătātìcĭus  | natāticius | **TLL-confirmed**: "natāticius (vel natātitius)", only the 2nd a long; grave dropped |

Also TLL-confirmed: abscīdo, cubitum, multifer, cōnsuētē (see tables above).
