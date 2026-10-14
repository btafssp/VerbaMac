# lsjcheck: regression harness

Headless checks of parsing and lexicon lookups (Latin and Greek) against the real databases. Compile `main.swift` together with the app's non-UI sources (Parsing and Lexicon), then run from the project root:

```sh
VERBAMAC_GREEK_DB=Resources/Lexicon/grc.sqlite \
VERBAMAC_MORPHEUS=Resources/Morpheus/bin/cruncher \
VERBAMAC_MORPHLIB=Resources/Morpheus/stemlib \
./lsjcheck Resources/Lexicon/lat.sqlite Resources/Lexicon/lat.sqlite
```

Expected result: ALL PASS. `Tools/macaudit` is a similar headless audit of L&S macrons; `Tools/tll_corrections.md` records quantity corrections checked against the TLL.
