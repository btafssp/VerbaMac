import Foundation
import SwiftUI
import AppKit

/// Shared per-window app state: search, language, analyses, selection, history.
@MainActor
final class AppState: ObservableObject {
    @Published var query: String = "" {
        didSet {
            guard !suppressHeadwordRefresh else { return }
            scheduleHeadwordRefresh()
        }
    }
    @Published var language: Language = .both
    @Published var analyses: [Analysis] = []
    @Published var selectedAnalysisID: Analysis.ID?
    @Published var currentArticle: LexiconArticle? {
        didSet { if !keepArticleSection { articleSection = nil } }
    }
    /// Section the article pane should scroll to (cross-ref "v. εἴδω B."); nil = top.
    @Published private(set) var articleSection: String?
    private var keepArticleSection = false

    private func showArticle(_ article: LexiconArticle?, section: String?) {
        keepArticleSection = true
        currentArticle = article
        articleSection = section
        keepArticleSection = false
    }
    @Published var isParsing: Bool = false
    @Published var statusMessage: String?
    @Published var showAbout: Bool = false

    // MARK: - Headword pane (Dictionary-style left list)
    @Published var headwords: [HeadwordHit] = []
    @Published var selectedHeadwordID: String?
    @Published var isUpdatingHeadwords: Bool = false

    // MARK: - In-article Find (lexicon WKWebView)
    @Published var showArticleFindBar: Bool = false
    @Published var articleFindString: String = ""
    /// Bumped to ask ArticleWebView to run a find / selection action.
    @Published var articleFindCommand: ArticleFindCommand?
    /// Bumped on every ⌘F: the find field must become first responder (even if already open).
    @Published private(set) var findFieldFocusToken: Int = 0
    /// Bumped when the find bar closes via Escape: focus returns to the lexicon.
    @Published private(set) var lexiconFocusToken: Int = 0
    /// True only when ⌘F opened the bar: the field takes focus on appear.
    /// ⌘G/⇧⌘G opening the bar must not steal focus.
    var findFocusPending = false
    func consumeFindFocusPending() -> Bool {
        defer { findFocusPending = false }
        return findFocusPending
    }

    /// Greek ignore-accents preference (`cruncher -n`).
    @Published var greekIgnoreAccents: Bool = true {
        didSet { rebuildParser() }
    }

    /// Back/Forward stops: successful searches, headword opens, cross-ref clicks.
    /// Each stores the exact article and pane state, so Back/Forward never re-search.
    @Published private(set) var navigation = NavigationHistory()
    /// Bumped by every navigation; async article loads from an older one are dropped.
    private var navigationGeneration = 0

    var canGoBack: Bool { navigation.canGoBack }
    var canGoForward: Bool { navigation.canGoForward }

    private(set) var parser: any Parser
    private var pipeline: ParserPipeline?
    let lexicon: LexiconStore
    private var headwordRefreshTask: Task<Void, Never>?
    /// Skip one debounce cycle when selectHeadword writes `query`.
    private var suppressHeadwordRefresh = false

    init(parser: (any Parser)? = nil, lexicon: LexiconStore = LexiconStore()) {
        self.lexicon = lexicon
        if let parser {
            self.parser = parser
            self.pipeline = parser as? ParserPipeline
        } else {
            let pipe = ParserPipeline(preferences: ParserPreferences(greekIgnoreAccents: true))
            self.pipeline = pipe
            self.parser = pipe
        }
        // Initial headword list (first page of L&S).
        Task { await refreshHeadwords(query: "", language: language) }
    }

    var selectedAnalysis: Analysis? {
        guard let id = selectedAnalysisID else { return nil }
        return analyses.first { $0.id == id }
    }

    /// Set parse language (Search menu ⌘0/⌘1/⌘2, cycle ⌘}/⌘{, or picker). Re-parses non-empty query.
    func setLanguage(_ lang: Language) {
        guard language != lang else { return }
        language = lang
        refreshHeadwordsNow()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            parseCurrentQuery()
        }
    }

    /// Cycle latin → greek → both → latin… (Search > Select Next Language ⌘}).
    func selectNextLanguage() {
        let all = Language.allCases
        guard let idx = all.firstIndex(of: language) else { return }
        setLanguage(all[(idx + 1) % all.count])
    }

    /// Cycle both → greek → latin → both… (Search > Select Previous Language ⌘{).
    func selectPreviousLanguage() {
        let all = Language.allCases
        guard let idx = all.firstIndex(of: language) else { return }
        setLanguage(all[(idx + all.count - 1) % all.count])
    }

    func parseCurrentQuery() {
        closeArticleFind()
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            analyses = []
            selectedAnalysisID = nil
            currentArticle = nil
            statusMessage = "Enter a Latin or Greek word form."
            return
        }
        Task { await runParse(q, recordHistory: true) }
    }

    /// Look up a form from Services / external caller (sets query and parses).
    func lookUp(_ raw: String) {
        let q = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        // Use first token / word-ish span for multi-word selections.
        let first = q.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).first.map(String.init) ?? q
        query = first
        parseCurrentQuery()
    }

    func selectAnalysis(_ analysis: Analysis?) {
        selectedAnalysisID = analysis?.id
        guard let analysis else {
            currentArticle = nil
            return
        }
        let gen = navigationGeneration
        Task {
            let article = await lexicon.article(for: analysis)
            await MainActor.run {
                guard gen == self.navigationGeneration else { return }
                self.currentArticle = article
                self.syncCurrentHistoryEntry()
                if article == nil {
                    self.statusMessage = "No lexicon article for \(analysis.lemma)."
                } else {
                    // Keep parser debug note if present.
                    if self.statusMessage?.contains("·") != true {
                        self.statusMessage = nil
                    }
                }
            }
        }
    }

    /// Move selection one row up (keyboard ↑). No-op at top.
    func selectPreviousAnalysis() {
        guard !analyses.isEmpty else { return }
        guard let id = selectedAnalysisID,
              let idx = analyses.firstIndex(where: { $0.id == id }) else {
            selectAnalysis(analyses.first)
            return
        }
        if idx > 0 {
            selectAnalysis(analyses[idx - 1])
        }
    }

    /// Move selection one row down (keyboard ↓). No-op at bottom.
    func selectNextAnalysis() {
        guard !analyses.isEmpty else { return }
        guard let id = selectedAnalysisID,
              let idx = analyses.firstIndex(where: { $0.id == id }) else {
            selectAnalysis(analyses.first)
            return
        }
        if idx + 1 < analyses.count {
            selectAnalysis(analyses[idx + 1])
        }
    }

    func goBack() {
        if let entry = navigation.back() { restore(entry) }
    }

    func goForward() {
        if let entry = navigation.forward() { restore(entry) }
    }

    /// Put the window back exactly as recorded: no parse, no headword query, no lookup.
    private func restore(_ entry: HistoryEntry) {
        closeArticleFind()
        navigationGeneration += 1
        headwordRefreshTask?.cancel()
        suppressHeadwordRefresh = true
        query = entry.query
        suppressHeadwordRefresh = false
        language = entry.language
        analyses = entry.analyses
        selectedAnalysisID = entry.selectedAnalysisID
        headwords = entry.headwords
        selectedHeadwordID = entry.selectedHeadwordID
        showArticle(entry.article, section: entry.section)
        statusMessage = nil
    }

    private func snapshot(kind: HistoryEntry.Kind, rowID: Int64?) -> HistoryEntry {
        HistoryEntry(kind: kind, query: query, language: language, analyses: analyses,
                     selectedAnalysisID: selectedAnalysisID, headwords: headwords,
                     selectedHeadwordID: selectedHeadwordID, articleRowID: rowID, article: currentArticle,
                     section: articleSection)
    }

    private func recordHistory(kind: HistoryEntry.Kind, rowID: Int64? = nil) {
        navigation.push(snapshot(kind: kind, rowID: rowID))
    }

    /// The current stop follows later changes on the same screen (article finished loading,
    /// another analysis picked, headword list arrived) while the search text is unchanged.
    private func syncCurrentHistoryEntry() {
        guard let cur = navigation.current, cur.query == query, cur.language == language else { return }
        navigation.updateCurrent { e in
            e.analyses = analyses
            e.selectedAnalysisID = selectedAnalysisID
            e.headwords = headwords
            e.selectedHeadwordID = selectedHeadwordID
            if e.kind == .search { e.article = currentArticle }
        }
    }


    // MARK: - Headwords

    /// Debounced live update of the left headword list from the search field.
    func scheduleHeadwordRefresh() {
        headwordRefreshTask?.cancel()
        let q = query
        let lang = language
        let task = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            await refreshHeadwords(query: q, language: lang)
        }
        headwordRefreshTask = task
    }

    func refreshHeadwordsNow() {
        headwordRefreshTask?.cancel()
        let q = query
        let lang = language
        headwordRefreshTask = Task { await refreshHeadwords(query: q, language: lang) }
    }

    /// Selecting a headword loads that lexicon article; analyses stay (Enter still parses).
    func selectHeadword(_ hit: HeadwordHit) {
        closeArticleFind()
        selectedHeadwordID = hit.id
        // Dictionary.app: keep the search text and the current prefix results; just
        // highlight the row and load its article. Record the lookup for Back/Forward.
        navigationGeneration += 1
        let gen = navigationGeneration
        Task {
            let article = await lexicon.article(for: hit)
            await MainActor.run {
                guard gen == self.navigationGeneration else { return }
                self.currentArticle = article
                if article != nil { self.recordHistory(kind: .headword, rowID: hit.rowID) }
                if article == nil {
                    self.statusMessage = "No lexicon article for \(hit.lemma)."
                } else if self.statusMessage?.contains("·") != true {
                    self.statusMessage = nil
                }
            }
        }
    }

    /// Clicked LSJ cross-reference ("v. εἴδω"): open the target article, record it for
    /// Back/Forward, and leave the search text and headword list alone.
    func openCrossReference(_ link: CrossReferenceLink) {
        let lemma = link.lemma, homograph = link.homograph
        closeArticleFind()
        navigationGeneration += 1
        let gen = navigationGeneration
        Task {
            guard let hit = await lexicon.resolveCrossReference(lemma: lemma, homograph: homograph) else {
                await MainActor.run { self.statusMessage = "No LSJ article for \(lemma)." }
                return
            }
            let article = await lexicon.article(for: hit)
            await MainActor.run {
                guard gen == self.navigationGeneration else { return }
                guard let article else {
                    self.statusMessage = "No LSJ article for \(lemma)."
                    return
                }
                self.selectedHeadwordID = self.headwords.contains(where: { $0.id == hit.id }) ? hit.id : nil
                self.showArticle(article, section: link.section)
                self.recordHistory(kind: .crossReference, rowID: hit.rowID)
                if self.statusMessage?.contains("·") != true { self.statusMessage = nil }
            }
        }
    }

    /// Keyboard: make sure a headword row is selected (first row) without loading it.
    func ensureHeadwordSelection() {
        if let id = selectedHeadwordID, headwords.contains(where: { $0.id == id }) { return }
        selectedHeadwordID = headwords.first?.id
    }

    /// ↑/↓ in the headword pane: move the highlight only (Enter opens).
    func moveHeadwordSelection(by delta: Int) {
        guard !headwords.isEmpty else { return }
        guard let id = selectedHeadwordID, let idx = headwords.firstIndex(where: { $0.id == id }) else {
            selectedHeadwordID = headwords.first?.id
            return
        }
        let next = min(max(idx + delta, 0), headwords.count - 1)
        selectedHeadwordID = headwords[next].id
    }

    /// Enter in the headword pane: same as clicking the selected row.
    func openSelectedHeadword() {
        guard let id = selectedHeadwordID, let hit = headwords.first(where: { $0.id == id }) else { return }
        selectHeadword(hit)
    }

    // MARK: - Article Find

    func showArticleFind() {
        findFocusPending = true
        showArticleFindBar = true
        findFieldFocusToken &+= 1
        // Seed from system Find pasteboard when our string is empty.
        if articleFindString.isEmpty {
            if let shared = NSPasteboard(name: .find).string(forType: .string), !shared.isEmpty {
                articleFindString = shared
            }
        }
        articleFindCommand = ArticleFindCommand(kind: .focusBar)
        if !articleFindString.isEmpty {
            // Run an initial forward find after the bar focuses.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.findNextInArticle()
            }
        }
    }

    /// Close the find bar and clear WebKit find highlights / selection.
    /// Called on Escape and whenever a new headword lookup starts.
    func closeArticleFind(returnFocusToLexicon: Bool = false) {
        if showArticleFindBar {
            showArticleFindBar = false
            articleFindCommand = ArticleFindCommand(kind: .clearHighlights)
        }
        if returnFocusToLexicon { lexiconFocusToken &+= 1 }
    }

    func findNextInArticle() {
        guard showArticleFindBar || !articleFindString.isEmpty else {
            showArticleFind()
            return
        }
        showArticleFindBar = true
        syncFindPasteboard()
        articleFindCommand = ArticleFindCommand(kind: .find(backwards: false))
    }

    func findPreviousInArticle() {
        showArticleFindBar = true
        syncFindPasteboard()
        articleFindCommand = ArticleFindCommand(kind: .find(backwards: true))
    }

    func useSelectionForFind() {
        articleFindCommand = ArticleFindCommand(kind: .useSelection)
    }

    func jumpToSelectionInArticle() {
        articleFindCommand = ArticleFindCommand(kind: .jumpToSelection)
    }

    func updateArticleFindString(_ value: String) {
        articleFindString = value
        syncFindPasteboard()
    }

    func applyCapturedFindSelection(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Dictionary.app ⌘E: set the find string only — no bar, no focus change.
        articleFindString = trimmed
        syncFindPasteboard()
    }


    // MARK: - Private

    private func rebuildParser() {
        let prefs = ParserPreferences(greekIgnoreAccents: greekIgnoreAccents)
        let pipe = ParserPipeline(preferences: prefs)
        pipeline = pipe
        parser = pipe
    }

    private func runParse(_ q: String, recordHistory: Bool) async {
        closeArticleFind()
        navigationGeneration += 1
        isParsing = true
        statusMessage = nil
        defer { isParsing = false }

        let lang = language
        let results = await parser.parse(q, language: lang)
        // Prefer lexicon gender (e.g. custos m.) over Morpheus masc/fem.
        var refined: [Analysis] = []
        for a in results {
            let art = await lexicon.article(for: a)
            var r = GenderRefiner.refine(a, articleHTML: art?.html)
            r.headwordLabel = await lexicon.headwordLabel(for: a)  // user decision: show the L&S headword
            refined.append(r)
        }

        refined = ParserPipeline.exactLemmaFirst(refined, query: q)
        analyses = refined
        let debug = pipeline?.lastDebugNote

        if let first = refined.first {
            selectAnalysis(first)
            var msg = refined.count == 1 ? "1 analysis" : "\(refined.count) analyses"
            if let debug, !debug.isEmpty {
                msg += " · \(debug)"
            }
            statusMessage = msg

            // History: only successful parses (non-empty results).
            // The article arrives async (selectAnalysis); syncCurrentHistoryEntry fills it in.
            if recordHistory {
                self.recordHistory(kind: .search)
            }
        } else {
            selectedAnalysisID = nil
            currentArticle = nil
            var msg = "No analysis for “\(q)”."
            if let debug, !debug.isEmpty {
                msg += " (\(debug))"
            }
            statusMessage = msg
            // Do not record failed parses in history.
        }
    }

    private func refreshHeadwords(query: String, language: Language) async {
        isUpdatingHeadwords = true
        let hits = await lexicon.headwords(matching: query, searchLanguage: language)
        guard !Task.isCancelled else {
            isUpdatingHeadwords = false
            return
        }
        headwords = hits
        defer { syncCurrentHistoryEntry() }
        if let sel = selectedHeadwordID, hits.contains(where: { $0.id == sel }) {
            // keep selection
        } else {
            selectedHeadwordID = nil
        }
        isUpdatingHeadwords = false
    }

    private func syncFindPasteboard() {
        let pb = NSPasteboard(name: .find)
        pb.clearContents()
        if !articleFindString.isEmpty {
            pb.setString(articleFindString, forType: .string)
        }
    }

}


/// One-shot command for the lexicon WKWebView find / selection bridge.
struct ArticleFindCommand: Equatable {
    enum Kind: Equatable {
        case focusBar
        case find(backwards: Bool)
        case useSelection
        case jumpToSelection
        case clearHighlights
    }
    let id = UUID()
    let kind: Kind

    static func == (lhs: ArticleFindCommand, rhs: ArticleFindCommand) -> Bool {
        lhs.id == rhs.id
    }
}
