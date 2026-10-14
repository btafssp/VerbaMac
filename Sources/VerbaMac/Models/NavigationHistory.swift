import Foundation

/// One Back/Forward stop: everything needed to put the window back exactly as it was,
/// without re-running a search (which could land on a different article).
struct HistoryEntry: Sendable {
    enum Kind: String, Sendable { case search, headword, crossReference }
    var kind: Kind
    var query: String
    var language: Language
    var analyses: [Analysis]
    var selectedAnalysisID: Analysis.ID?
    var headwords: [HeadwordHit]
    var selectedHeadwordID: String?
    /// LSJ / L&S row of the shown article when known (headword or cross-ref).
    var articleRowID: Int64?
    var article: LexiconArticle?
    /// Section anchor the article was scrolled to ("B" for "v. εἴδω B."), nil = top.
    var section: String? = nil

    /// Same stop (don't push a duplicate): same kind of view of the same article for the same text.
    func isSameStop(as other: HistoryEntry) -> Bool {
        guard query == other.query, language == other.language else { return false }
        if let a = articleRowID, let b = other.articleRowID { return a == b && section == other.section }
        if articleRowID != nil || other.articleRowID != nil { return false }
        return kind == other.kind && article?.lemma == other.article?.lemma && article?.html == other.article?.html
    }
}

/// Browser-style stack: push truncates forward entries; back/forward move the cursor.
struct NavigationHistory: Sendable {
    private(set) var entries: [HistoryEntry] = []
    private(set) var index: Int = -1

    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index >= 0 && index < entries.count - 1 }
    var current: HistoryEntry? { entries.indices.contains(index) ? entries[index] : nil }

    /// Returns false when `entry` duplicates the current stop (then it just refreshes it).
    @discardableResult
    mutating func push(_ entry: HistoryEntry) -> Bool {
        if let cur = current, cur.isSameStop(as: entry) {
            entries[index] = entry
            return false
        }
        if canGoForward { entries = Array(entries.prefix(index + 1)) }
        entries.append(entry)
        index = entries.count - 1
        return true
    }

    /// Update the current stop in place (article finished loading, analysis re-selected).
    mutating func updateCurrent(_ change: (inout HistoryEntry) -> Void) {
        guard entries.indices.contains(index) else { return }
        change(&entries[index])
    }

    mutating func back() -> HistoryEntry? {
        guard canGoBack else { return nil }
        index -= 1
        return entries[index]
    }

    mutating func forward() -> HistoryEntry? {
        guard canGoForward else { return nil }
        index += 1
        return entries[index]
    }
}
