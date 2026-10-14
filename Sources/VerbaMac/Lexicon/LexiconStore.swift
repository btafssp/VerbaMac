import Foundation

/// Lexicon lookup: SQLite + zstd.
///
/// Schema (read-only in the app) — see SPEC.md:
/// ```sql
/// CREATE TABLE articles (
///   id INTEGER PRIMARY KEY,
///   lemma TEXT NOT NULL,
///   lemma_norm TEXT NOT NULL,
///   lang TEXT NOT NULL CHECK (lang IN ('lat','grc')),
///   html_zstd BLOB NOT NULL,
///   plain TEXT
/// );
/// CREATE INDEX idx_norm ON articles(lang, lemma_norm);
/// CREATE VIRTUAL TABLE articles_fts USING fts5(lemma, plain, content='articles');
/// CREATE TABLE zdicts (lang TEXT PRIMARY KEY, dict BLOB NOT NULL);
/// ```
actor LexiconStore {
    private let sqlite: SQLiteLexiconDB?
    /// LSJ (`grc.sqlite`), opened alongside L&S. Nil until the Greek DB is installed.
    private let greekSQLite: SQLiteLexiconDB?
    /// True when a SQLite file was opened .
    private(set) var usingSQLite: Bool = false
    /// Lazily built per DB: article id → homograph number (λογάς¹, λογάς²).
    private var homographCache: [ObjectIdentifier: [Int64: Int]] = [:]

    private func homographs(in db: SQLiteLexiconDB) -> [Int64: Int] {
        let key = ObjectIdentifier(db)
        if let cached = homographCache[key] { return cached }
        let map = db.homographNumbers()
        homographCache[key] = map
        return map
    }

    /// Prefer Application Support / env override, then bundled `Lexicon/lat.sqlite`.
    init(databaseURL: URL? = nil) {

        let url = databaseURL ?? Self.resolveDatabaseURL()
        if let url, let db = SQLiteLexiconDB(url: url) {
            self.sqlite = db
            self.usingSQLite = true
        } else {
            self.sqlite = nil
            self.usingSQLite = false
        }
        if let gurl = Self.resolveGreekDatabaseURL(), gurl != url, let gdb = SQLiteLexiconDB(url: gurl) {
            self.greekSQLite = gdb
            self.usingSQLite = true
        } else {
            self.greekSQLite = nil
        }
    }

    /// DB serving `language`: Greek → grc.sqlite when present, else the main DB (seed/lexica may hold grc rows).
    private func db(for language: LexiconLanguage) -> SQLiteLexiconDB? {
        if language == .greek, let greekSQLite { return greekSQLite }
        return sqlite
    }

    /// Greek join key: Morpheus homograph digits (εἰμί1) and compound hyphens are not part of LSJ `lemma_norm`.
    private static func lookupNorm(_ language: LexiconLanguage, _ norm: String) -> String {
        guard language == .greek else { return norm }
        // Also drop Morpheus compound hyphens (ἀνα-δράω → ἀναδράω).
        var out = String(norm.unicodeScalars.filter {
            !CharacterSet.decimalDigits.contains($0) && $0 != "-"
        }.map(Character.init))
        // BetaCode.toDisplay may leave a word-final medial σ (lo/gos → λόγοσ); LSJ keys use ς.
        if out.hasSuffix("σ") { out = String(out.dropLast()) + "ς" }
        return out
    }

    /// Article for a headword-pane row (exact homograph when rowID is known).
    func article(for hit: HeadwordHit) -> LexiconArticle? {
        Self.present(rawArticle(for: hit))
    }

    /// Display-time Latin quantity policy (TLL-style macrons; see LatinQuantity).
    private static func present(_ a: LexiconArticle?) -> LexiconArticle? {
        guard let a, a.language == .latin else { return a }
        return LexiconArticle(id: a.id, lemma: LatinQuantity.display(a.lemma), lemmaNorm: a.lemmaNorm,
                              language: a.language, html: LatinQuantity.displayHTML(a.html), plain: a.plain)
    }

    private func rawArticle(for hit: HeadwordHit) -> LexiconArticle? {
        if let rowID = hit.rowID, let db = db(for: hit.language), let row = db.row(id: rowID) {
            return decode(row, language: hit.language)
        }
        return rawArticle(language: hit.language, lemmaNorm: hit.lemmaNorm)
    }

    /// Resolve an LSJ cross-reference (`<a class="xref">`) to one article row.
    /// Match by `lemma_norm`; among those prefer the exact lemma (accents kept, case
    /// folded: Perseus marks some targets with a capital `*`). A homograph number picks
    /// the n-th exact match in lexicon order, as in the headword pane (εἰμί¹/εἶμι).
    func resolveCrossReference(lemma: String, homograph: Int? = nil, language: LexiconLanguage = .greek) -> HeadwordHit? {
        guard let db = db(for: language) else { return nil }
        let norm = Self.lookupNorm(language, language == .greek ? MorphPreprocess.greekBase(lemma) : MorphPreprocess.latinLookupKey(lemma))
        let rows = db.candidates(language: language, lemmaNorm: norm)
        guard !rows.isEmpty else { return nil }
        let want = Self.foldCase(lemma)
        let exact = rows.filter { Self.foldCase($0.lemma) == want }
        let pool = exact.isEmpty ? rows : exact
        var pick = pool[0]
        if let homograph, homograph >= 1, homograph <= pool.count { pick = pool[homograph - 1] }
        let homs = homographs(in: db)
        return HeadwordHit(lemma: pick.lemma, lemmaNorm: norm, language: language,
                           rowID: pick.id, homographNumber: homs[pick.id])
    }

    private static func foldCase(_ s: String) -> String {
        s.precomposedStringWithCanonicalMapping.lowercased().precomposedStringWithCanonicalMapping
    }

    /// Look up by concrete language + normalized lemma.
    func article(language: LexiconLanguage, lemmaNorm: String) -> LexiconArticle? {
        Self.present(rawArticle(language: language, lemmaNorm: lemmaNorm))
    }

    private func rawArticle(language: LexiconLanguage, lemmaNorm: String) -> LexiconArticle? {
        articleFromSQLite(language: language, lemmaNorm: lemmaNorm)
    }

    /// Convenience from an analysis selection.
    /// Latin: the L&S headword an analysis resolves to, labelled exactly as in the headword pane.
    func headwordLabel(for analysis: Analysis) -> String? {
        guard analysis.language == .latin, let db = db(for: .latin) else { return nil }
        let rows = db.candidates(language: .latin, lemmaNorm: Self.lookupNorm(.latin, analysis.lemmaNorm))
        guard !rows.isEmpty else { return nil }
        var pick = rows[0]
        if let n = analysis.homograph, n >= 1, n <= rows.count { pick = rows[n - 1] }
        return HeadwordHit(lemma: pick.lemma, lemmaNorm: analysis.lemmaNorm, language: .latin,
                           rowID: pick.id, homographNumber: homographs(in: db)[pick.id]).displayLemma
    }

    func article(for analysis: Analysis) -> LexiconArticle? {
        // Morpheus `#n` → nth lexicon row with that lemma_norm (id order). Without this every
        // homograph opened the first row (abdico#2 showed ab-dĭco, 1 instead of ab-dīco, 3).
        if let n = analysis.homograph, n >= 1, let db = db(for: analysis.language) {
            let rows = db.candidates(language: analysis.language,
                                     lemmaNorm: Self.lookupNorm(analysis.language, analysis.lemmaNorm))
            if n <= rows.count, let row = db.row(id: rows[n - 1].id) {
                return Self.present(decode(row, language: analysis.language))
            }
        }
        return article(language: analysis.language, lemmaNorm: analysis.lemmaNorm)
    }

    func backendDescription() -> String {
        if usingSQLite {
            var parts: [String] = []
            if let sqlite { parts.append("\(sqlite.articleCount())") }
            if let greekSQLite { parts.append("LSJ \(greekSQLite.articleCount())") }
            return "SQLite (\(parts.joined(separator: " + ")) articles)"
        }
        return "no lexicon database"
    }


    /// Live headword list for the left pane (prefix on `lemma_norm`).
    /// Latin → L&S. Greek → LSJ (Unicode Greek, or ASCII read as Beta Code).
    /// Both → LSJ when the query is in Greek script, else L&S.
    func headwords(matching query: String, searchLanguage: Language, limit: Int = 80) -> [HeadwordHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lang: LexiconLanguage
        switch searchLanguage {
        case .latin: lang = .latin
        case .greek: lang = .greek
        case .both:
            if MorphPreprocess.looksGreek(trimmed) || trimmed.contains(where: { ")(/\\=|".contains($0) }) {
                lang = .greek
            } else {
                // Plain ASCII: Latin headwords, else read as Beta Code Greek ("oida" → οἶδα).
                let latin = headwords(matching: trimmed, searchLanguage: .latin, limit: limit)
                if !latin.isEmpty || trimmed.isEmpty { return latin }
                return headwords(matching: trimmed, searchLanguage: .greek, limit: limit)
            }
        }
        let prefix: String
        if lang == .greek {
            guard db(for: .greek)?.hasLanguage(.greek) == true else {
                return []
            }
            let greek = MorphPreprocess.looksGreek(trimmed) ? trimmed : BetaCode.toDisplay(trimmed)
            prefix = MorphPreprocess.greekBase(greek)
        } else {
            prefix = MorphPreprocess.latinLookupKey(trimmed)
        }

        if let db = db(for: lang), db.hasLanguage(lang) {
            var rows = db.headwords(prefix: prefix, language: lang, limit: limit)
            // Typed medial σ at the end of a prefix should also find final-ς lemmas (λογοσ → λόγος).
            // And vice versa: Beta Code "pas" displays as πας but should still list πᾶσα.
            if lang == .greek, prefix.hasSuffix("σ") || prefix.hasSuffix("ς") {
                let alt = String(prefix.dropLast()) + (prefix.hasSuffix("σ") ? "ς" : "σ")
                rows += db.headwords(prefix: alt, language: lang, limit: limit)
                rows.sort { ($0.lemmaNorm, $0.id) < ($1.lemmaNorm, $1.id) }
                rows = Array(rows.prefix(limit))
            }
            let homs = homographs(in: db)
            return rows.compactMap { row in
                guard let lexLang = LexiconLanguage(rawValue: row.lang) else { return nil }
                return HeadwordHit(lemma: row.lemma, lemmaNorm: row.lemmaNorm, language: lexLang,
                                   rowID: row.id, homographNumber: homs[row.id])
            }
        }

        return []
    }

    // MARK: - SQLite path

    private func articleFromSQLite(language: LexiconLanguage, lemmaNorm: String) -> LexiconArticle? {
        guard let db = db(for: language) else { return nil }
        guard let row = db.row(language: language, lemmaNorm: Self.lookupNorm(language, lemmaNorm)) else {
            return nil
        }
        return decode(row, language: language)
    }

    private func decode(_ row: SQLiteLexiconDB.Row, language: LexiconLanguage) -> LexiconArticle? {
        let dict = db(for: language)?.zdicts[row.lang]
        if let data = ZstdCodec.decompress(row.htmlZstd, dictionary: dict),
           let html = String(data: data, encoding: .utf8) {
            return LexiconArticle(
                lemma: row.lemma,
                lemmaNorm: row.lemmaNorm,
                language: language,
                html: html,
                plain: row.plain
            )
        }
        // Dict-zstd not yet decompressible via Compression.framework: degrade to plain,
        if let plain = row.plain, !plain.isEmpty {
            let escaped = plain
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
            let html = """
            <article class="entry"><h1>\(Self.escapeHTML(row.lemma))</h1>\
            <pre class="plain">\(escaped)</pre>\
            <p class="note"><i>zstd dictionary decompress pending (libzstd); showing plaintext.</i></p>\
            </article>
            """
            return LexiconArticle(
                lemma: row.lemma,
                lemmaNorm: row.lemmaNorm,
                language: language,
                html: html,
                plain: plain
            )
        }
        return nil
    }

    private static func escapeHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func key(lang: LexiconLanguage, lemmaNorm: String) -> String {
        "\(lang.rawValue):\(lemmaNorm)"
    }

    /// LSJ: `VERBAMAC_GREEK_DB` → Application Support `VerbaMac/grc.sqlite` → bundle `grc.sqlite`.
    static func resolveGreekDatabaseURL() -> URL? {
        if let env = ProcessInfo.processInfo.environment["VERBAMAC_GREEK_DB"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if FileManager.default.isReadableFile(atPath: url.path) { return url }
        }
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let url = appSupport.appendingPathComponent("VerbaMac/grc.sqlite")
            if FileManager.default.isReadableFile(atPath: url.path),
               !isStale(url, comparedTo: bundledURL(name: "grc")) { return url }
        }
        return bundledURL(name: "grc")
    }

    /// Bundled `<name>.sqlite` (Lexicon/ subdirectory first, then bundle root).
    static func bundledURL(name: String) -> URL? {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: "sqlite", subdirectory: "Lexicon") { return url }
        if let url = Bundle.module.url(forResource: name, withExtension: "sqlite") { return url }
        #endif
        if let url = Bundle.main.url(forResource: name, withExtension: "sqlite", subdirectory: "Lexicon") { return url }
        return Bundle.main.url(forResource: name, withExtension: "sqlite")
    }

    /// True when `url` is older than the bundled DB (so the bundle wins).
    static func isStale(_ url: URL, comparedTo bundled: URL?) -> Bool {
        guard let bundled else { return false }
        func mtime(_ u: URL) -> Date? {
            (try? FileManager.default.attributesOfItem(atPath: u.path))?[.modificationDate] as? Date
        }
        guard let a = mtime(url), let b = mtime(bundled) else { return false }
        return a < b
    }

    /// Resolution order: `VERBAMAC_LEXICON_DB` → Application Support → bundle.
    /// Prefer full `lat.sqlite` / `lexica.sqlite`.
    static func resolveDatabaseURL() -> URL? {
        if let env = ProcessInfo.processInfo.environment["VERBAMAC_LEXICON_DB"], !env.isEmpty {
            let url = URL(fileURLWithPath: env)
            if FileManager.default.isReadableFile(atPath: url.path) { return url }
        }

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let candidates = [
                appSupport.appendingPathComponent("VerbaMac/lexica.sqlite"),
                appSupport.appendingPathComponent("VerbaMac/lat.sqlite"),
            ]
            for url in candidates where FileManager.default.isReadableFile(atPath: url.path) {
                // An older Application Support copy (e.g. a Sep 28 import) must not shadow
                // a newer bundled re-import: it hid L&S rows such as the 2nd ab-dīco.
                if isStale(url, comparedTo: bundledURL(name: "lat")) { continue }
                return url
            }
        }

        for name in ["lat", "lexica"] {
            if let url = bundledURL(name: name) { return url }
        }
        return nil
    }
}
