import Foundation
import SQLite3

/// SQLITE_TRANSIENT: SQLite copies the binding (safe for Swift string lifetimes).
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// Read-only SQLite access for the lexicon schema (`articles`, `zdicts`, FTS5).
///
/// Prepared statements are cached per SQL string and reused (reset + clear bindings);
/// a lock serializes access, so the type is safe to share across tasks.
final class SQLiteLexiconDB: @unchecked Sendable {
    private var db: OpaquePointer?
    private(set) var zdicts: [String: Data] = [:]
    private var statements: [String: OpaquePointer] = [:]
    private var languagePresence: [LexiconLanguage: Bool] = [:]
    private let lock = NSLock()

    struct Row: Sendable {
        let lemma: String
        let lemmaNorm: String
        let lang: String
        let htmlZstd: Data
        let plain: String?
    }

    init?(url: URL) {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            return nil
        }
        self.db = handle
        loadZdicts()
        if articleCount() == 0 {
            finalizeStatements()
            sqlite3_close(handle)
            self.db = nil
            return nil
        }
    }

    deinit {
        finalizeStatements()
        if let db { sqlite3_close(db) }
    }

    // MARK: - Statement cache

    private func finalizeStatements() {
        for stmt in statements.values { sqlite3_finalize(stmt) }
        statements.removeAll()
    }

    /// Run `body` with the cached statement for `sql`, bound by `bind`. Caller holds no lock.
    private func withStatement<T>(_ sql: String, bind: (OpaquePointer) -> Void = { _ in },
                                  _ body: (OpaquePointer) -> T) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard let db else { return nil }
        let stmt: OpaquePointer
        if let cached = statements[sql] {
            stmt = cached
        } else {
            var fresh: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &fresh, nil) == SQLITE_OK, let fresh else {
                sqlite3_finalize(fresh)
                return nil
            }
            statements[sql] = fresh
            stmt = fresh
        }
        defer { sqlite3_reset(stmt); sqlite3_clear_bindings(stmt) }
        bind(stmt)
        return body(stmt)
    }

    private static func bindText(_ stmt: OpaquePointer, _ index: Int32, _ value: String) {
        _ = value.withCString { sqlite3_bind_text(stmt, index, $0, -1, SQLITE_TRANSIENT) }
    }

    private static func text(_ stmt: OpaquePointer, _ col: Int32) -> String {
        sqlite3_column_text(stmt, col).map { String(cString: $0) } ?? ""
    }

    /// Columns: lemma, lemma_norm, lang, html_zstd, plain.
    private static func readRow(_ stmt: OpaquePointer) -> Row {
        let blobLen = Int(sqlite3_column_bytes(stmt, 3))
        var htmlZstd = Data()
        if let blob = sqlite3_column_blob(stmt, 3), blobLen > 0 {
            htmlZstd = Data(bytes: blob, count: blobLen)
        }
        var plain: String? = nil
        if sqlite3_column_type(stmt, 4) != SQLITE_NULL, let p = sqlite3_column_text(stmt, 4) {
            plain = String(cString: p)
        }
        return Row(lemma: text(stmt, 0), lemmaNorm: text(stmt, 1), lang: text(stmt, 2),
                   htmlZstd: htmlZstd, plain: plain)
    }

    // MARK: - Queries

    private func loadZdicts() {
        _ = withStatement("SELECT lang, dict FROM zdicts") { stmt in
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let blob = sqlite3_column_blob(stmt, 1) else { continue }
                zdicts[Self.text(stmt, 0)] = Data(bytes: blob, count: Int(sqlite3_column_bytes(stmt, 1)))
            }
        }
    }

    func articleCount() -> Int {
        withStatement("SELECT COUNT(*) FROM articles") { stmt in
            sqlite3_step(stmt) == SQLITE_ROW ? Int(sqlite3_column_int64(stmt, 0)) : 0
        } ?? 0
    }

    /// First article (id order) with this `lemma_norm`.
    func row(language: LexiconLanguage, lemmaNorm: String) -> Row? {
        let sql = """
        SELECT lemma, lemma_norm, lang, html_zstd, plain
        FROM articles WHERE lang = ? AND lemma_norm = ? ORDER BY id LIMIT 1
        """
        return withStatement(sql, bind: {
            Self.bindText($0, 1, language.rawValue)
            Self.bindText($0, 2, lemmaNorm)
        }) { stmt in
            sqlite3_step(stmt) == SQLITE_ROW ? Self.readRow(stmt) : nil
        } ?? nil
    }

    /// Fetch one article by primary key (headword pane homographs).
    func row(id: Int64) -> Row? {
        let sql = "SELECT lemma, lemma_norm, lang, html_zstd, plain FROM articles WHERE id = ?"
        return withStatement(sql, bind: { sqlite3_bind_int64($0, 1, id) }) { stmt in
            sqlite3_step(stmt) == SQLITE_ROW ? Self.readRow(stmt) : nil
        } ?? nil
    }

    /// All (id, lemma) rows sharing `lemmaNorm`, in lexicon (id) order.
    func candidates(language: LexiconLanguage, lemmaNorm: String) -> [(id: Int64, lemma: String)] {
        let sql = "SELECT id, lemma FROM articles WHERE lang = ? AND lemma_norm = ? ORDER BY id"
        return withStatement(sql, bind: {
            Self.bindText($0, 1, language.rawValue)
            Self.bindText($0, 2, lemmaNorm)
        }) { stmt in
            var out: [(id: Int64, lemma: String)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                out.append((sqlite3_column_int64(stmt, 0), Self.text(stmt, 1)))
            }
            return out
        } ?? []
    }

    /// Prefix match on `lemma_norm` for the left headword pane.
    /// `prefix` should already be normalized (e.g. MorphPreprocess.latinLookupKey).
    func headwords(prefix: String, language: LexiconLanguage, limit: Int = 80) -> [(lemma: String, lemmaNorm: String, lang: String, id: Int64)] {
        let lim = Int32(max(1, min(limit, 500)))
        // Index range scan on idx_norm(lang, lemma_norm) instead of LIKE (which
        // cannot use the index for non-ASCII and scanned every LSJ row).
        let sql = prefix.isEmpty
            ? "SELECT lemma, lemma_norm, lang, id FROM articles WHERE lang = ? ORDER BY lemma_norm, id LIMIT ?"
            : "SELECT lemma, lemma_norm, lang, id FROM articles WHERE lang = ? AND lemma_norm >= ? AND lemma_norm < ? ORDER BY lemma_norm, id LIMIT ?"
        return withStatement(sql, bind: { stmt in
            Self.bindText(stmt, 1, language.rawValue)
            if prefix.isEmpty {
                sqlite3_bind_int(stmt, 2, lim)
            } else {
                Self.bindText(stmt, 2, prefix)
                Self.bindText(stmt, 3, prefix + "\u{10FFFF}")
                sqlite3_bind_int(stmt, 4, lim)
            }
        }) { stmt in
            var rows: [(lemma: String, lemmaNorm: String, lang: String, id: Int64)] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                rows.append((Self.text(stmt, 0), Self.text(stmt, 1), Self.text(stmt, 2), sqlite3_column_int64(stmt, 3)))
            }
            return rows
        } ?? []
    }

    /// Homograph numbers: article id → 1-based position among rows with the same
    /// headword (id order = lexicon order). Only headwords with >1 row appear.
    /// Greek groups by exact `lemma`; Latin by the *displayed* lemma, so L&S homographs
    /// that differ only by a dropped breve (cĭtŏ / cĭto → cito) still get cito¹ / cito².
    /// Rows in one group always share `lemma_norm`, so only duplicated norms are scanned.
    func homographNumbers() -> [Int64: Int] {
        let sql = """
        SELECT a.id, a.lang, a.lemma FROM articles a
        JOIN (SELECT lang, lemma_norm FROM articles GROUP BY lang, lemma_norm HAVING COUNT(*) > 1) d
          ON a.lang = d.lang AND a.lemma_norm = d.lemma_norm
        ORDER BY a.id
        """
        return withStatement(sql) { stmt in
            var groups: [String: [Int64]] = [:]
            while sqlite3_step(stmt) == SQLITE_ROW {
                let lang = Self.text(stmt, 1)
                let lemma = Self.text(stmt, 2)
                let key = lang + "\u{1F}" + (lang == LexiconLanguage.latin.rawValue ? LatinQuantity.display(lemma) : lemma)
                groups[key, default: []].append(sqlite3_column_int64(stmt, 0))
            }
            var out: [Int64: Int] = [:]
            for ids in groups.values where ids.count > 1 {
                for (i, id) in ids.enumerated() { out[id] = i + 1 }
            }
            return out
        } ?? [:]
    }

    /// True when the DB has at least one article for `language` (cached).
    func hasLanguage(_ language: LexiconLanguage) -> Bool {
        lock.lock()
        if let known = languagePresence[language] { lock.unlock(); return known }
        lock.unlock()
        let present = withStatement("SELECT 1 FROM articles WHERE lang = ? LIMIT 1",
                                    bind: { Self.bindText($0, 1, language.rawValue) }) { stmt in
            sqlite3_step(stmt) == SQLITE_ROW
        } ?? false
        lock.lock(); languagePresence[language] = present; lock.unlock()
        return present
    }
}
