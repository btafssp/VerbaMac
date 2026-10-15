import SwiftUI
import AppKit


/// SwiftUI focus for the search field. Analyses + lexicon use AppKit firstResponder
/// (`analysesKeyboardActive` / `lexiconKeyboardActive`) so keys reach custom hosts.
enum PaneFocus: Hashable {
    case search
}

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @FocusState private var paneFocus: PaneFocus?
    /// When true, analyses AppKit key host is first responder (↑/↓/Return).
    @State private var analysesKeyboardActive = false
    /// When true, lexicon WKWebView is made first responder for arrow/page scrolling.
    @State private var lexiconKeyboardActive = false
    @State private var headwordsKeyboardActive = false
    /// Local key monitor: Tab / Shift-Tab out of the search field (field editor eats Tab otherwise).
    @State private var tabMonitor: Any?
    @AppStorage(LexiconColorScheme.storageKey) private var schemeRaw: String = LexiconColorScheme.appDefault.rawValue
    @AppStorage(ContentTextSize.storageKey) private var contentTextSize: Double = ContentTextSize.defaultPoints
    @State private var analysisPaneHeight: CGFloat = 160
    @State private var splitAreaHeight: CGFloat = 480
    @State private var measuredAnalysisHeight: CGFloat = 0
    @State private var isDraggingDivider = false
    /// Debounce token so GeometryReader preference thrash during layout/drag doesn't snap-fight.
    @State private var measureSnapWorkItem: DispatchWorkItem?

    private var colorScheme: LexiconColorScheme {
        LexiconColorScheme(rawValue: schemeRaw) ?? .appDefault
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(state: state, focus: $paneFocus)

            Divider()

            // Dictionary-like: headwords | analyses + article
            HSplitView {
                HeadwordListView(
                    state: state,
                    colorScheme: colorScheme,
                    contentTextSize: contentTextSize,
                    keyboardActive: headwordsKeyboardActive,
                    onKeyboardResigned: { headwordsKeyboardActive = false },
                    onActivate: activateHeadwords,
                    onShiftTab: { activateSearch(selectAll: true) },
                    onTab: { if !state.analyses.isEmpty { activateAnalyses() } }
                )
                .frame(minWidth: 140, idealWidth: 180, maxWidth: 280)

                SnappingVSplitView(
                    topHeight: $analysisPaneHeight,
                    isDragging: $isDraggingDivider
                ) {
                    AnalysisListView(
                        state: state,
                        colorScheme: colorScheme,
                        contentTextSize: contentTextSize,
                        analysesKeyboardActive: analysesKeyboardActive,
                        onKeyboardResigned: { analysesKeyboardActive = false },
                        onActivateAnalyses: activateAnalyses,
                        onTransferToLexicon: activateLexicon,
                        onTransferToSearch: { activateSearch(selectAll: true) }
                    )
                } bottom: {
                    ArticleView(
                        state: state,
                        article: state.currentArticle,
                        statusMessage: state.statusMessage,
                        colorScheme: colorScheme,
                        contentTextSize: contentTextSize,
                        lexiconFocused: lexiconKeyboardActive,
                        onShiftTab: activateAnalyses
                    )
                }
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(key: SplitHeightKey.self, value: geo.size.height)
                    }
                )
                .onPreferenceChange(SplitHeightKey.self) { newHeight in
                    // Debounce: avoid layout thrash while the divider is mid-drag.
                    scheduleSplitHeightUpdate(newHeight)
                }
                .onPreferenceChange(AnalysisContentHeightKey.self) { height in
                    scheduleMeasuredHeightUpdate(height)
                }
            }
        }
        .frame(minWidth: 780, minHeight: 480)
        .background(colorScheme.paneBackground)
        .onAppear {
            installTabMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                activateSearch()
            }
            // Snap empty / residual height so divider sits under content.
            DispatchQueue.main.async {
                snapAnalysisPane(for: state.analyses.count)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .verbaFocusSearch)) { _ in
            state.closeArticleFind()
            activateSearch()
        }
        .onChange(of: state.findFieldFocusToken) { _, _ in
            // ⌘F: release the analyses host / lexicon / search so they don't reclaim
            // first responder from the find field on the next update.
            analysesKeyboardActive = false
            lexiconKeyboardActive = false
            paneFocus = nil
        }
        .onDisappear {
            if let tabMonitor { NSEvent.removeMonitor(tabMonitor) }
            tabMonitor = nil
        }
        .onChange(of: paneFocus) { _, f in
            // Clicking the search field: release the AppKit hosts so they don't reclaim focus.
            if f == .search {
                analysesKeyboardActive = false
                lexiconKeyboardActive = false
                headwordsKeyboardActive = false
            }
        }
        .onChange(of: state.lexiconFocusToken) { _, _ in
            activateLexicon()
        }
        .onReceive(NotificationCenter.default.publisher(for: .verbaLexiconColorSchemeChanged)) { note in
            if let raw = note.object as? String {
                schemeRaw = raw
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .verbaContentTextSizeChanged)) { note in
            if let value = note.object as? Double {
                contentTextSize = value
            } else {
                contentTextSize = ContentTextSize.stored()
            }
        }
        .onChange(of: state.analyses) { _, analyses in
            measuredAnalysisHeight = 0
            snapAnalysisPane(for: analyses.count)
        }
        .onChange(of: state.isParsing) { _, parsing in
            // Snap once parsing finishes (count may be unchanged on re-parse).
            if !parsing {
                // Delay one runloop so List lays out before we measure/snap.
                DispatchQueue.main.async {
                    snapAnalysisPane(for: state.analyses.count)
                }
                // After Enter/Parse with hits: move keyboard focus to analyses.
                // Brief delay so the analyses stack is focusable and search has resigned.
                if !state.analyses.isEmpty {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        activateAnalyses()
                    }
                }
            }
        }
        .onChange(of: isDraggingDivider) { _, dragging in
            if dragging {
                measureSnapWorkItem?.cancel()
            }
        }
        .sheet(isPresented: $state.showAbout) {
            AboutView()
        }
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                Button {
                    state.showAbout = true
                } label: {
                    Label("About VerbaMac", systemImage: "info.circle")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                LexiconShareButton(article: state.currentArticle)
                    .help("Share")
            }
        }
    }


    private func activateSearch(selectAll: Bool = true) {
        headwordsKeyboardActive = false
        analysesKeyboardActive = false
        lexiconKeyboardActive = false
        paneFocus = .search
        guard selectAll else { return }
        // Field editor appears after SwiftUI focus settles — select query text (Dictionary-like).
        DispatchQueue.main.async { Self.selectFocusedSearchText() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) { Self.selectFocusedSearchText() }
    }

    private static func selectFocusedSearchText() {
        guard let window = NSApp.keyWindow else { return }
        if let field = window.firstResponder as? NSTextField {
            field.currentEditor()?.selectAll(nil)
            return
        }
        if let editor = window.firstResponder as? NSTextView {
            editor.selectAll(nil)
            return
        }
        if let editor = window.fieldEditor(false, for: nil) {
            editor.selectAll(nil)
        }
    }

    private func activateAnalyses() {
        headwordsKeyboardActive = false
        lexiconKeyboardActive = false
        paneFocus = nil
        analysesKeyboardActive = true
    }

    private func activateLexicon() {
        headwordsKeyboardActive = false
        analysesKeyboardActive = false
        paneFocus = nil
        lexiconKeyboardActive = true
    }

    /// Search → headword list (Dictionary.app Tab order).
    private func activateHeadwords() {
        guard !state.headwords.isEmpty else { return }
        analysesKeyboardActive = false
        lexiconKeyboardActive = false
        paneFocus = nil
        state.ensureHeadwordSelection()
        headwordsKeyboardActive = true
    }

    private func installTabMonitor() {
        guard tabMonitor == nil else { return }
        tabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only plain Tab while this window's search field is focused.
            guard event.keyCode == 48, paneFocus == .search,
                  event.window?.isKeyWindow == true else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags.subtracting([.shift, .capsLock, .numericPad, .function]).isEmpty,
                  !flags.contains(.shift) else { return event }
            guard !state.headwords.isEmpty else { return event }
            activateHeadwords()
            return nil
        }
    }

    private func scheduleSplitHeightUpdate(_ newHeight: CGFloat) {
        guard !isDraggingDivider else { return }
        if abs(splitAreaHeight - newHeight) < 0.5 { return }
        splitAreaHeight = newHeight
    }

    private func scheduleMeasuredHeightUpdate(_ height: CGFloat) {
        guard !isDraggingDivider else { return }
        measureSnapWorkItem?.cancel()
        let work = DispatchWorkItem {
            guard !isDraggingDivider else { return }
            measuredAnalysisHeight = height
            if height > 0 {
                snapAnalysisPane(for: state.analyses.count)
            }
        }
        measureSnapWorkItem = work
        // Debounce preference writes from GeometryReader during layout / scroll.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: work)
    }

    private func snapAnalysisPane(for count: Int) {
        guard !isDraggingDivider else { return }
        let available = max(splitAreaHeight, 320)
        let estimated = AnalysisPaneSizing.idealTopHeight(
            analysisCount: count,
            availableHeight: available
        )
        // Prefer measured content height (flush under rows) when available,
        // plus snap padding so the last row isn't clipped by the divider.
        let raw: CGFloat
        if measuredAnalysisHeight > 1 {
            raw = measuredAnalysisHeight + AnalysisPaneSizing.snapPadding
        } else {
            raw = estimated
        }
        let ideal = AnalysisPaneSizing.clampTopHeight(raw, availableHeight: available)
        // Never shrink below the estimate when we have rows — avoids under-measure clip.
        let floorIdeal = count > 0 ? max(ideal, min(estimated, available * 0.52)) : ideal
        withAnimation(.easeInOut(duration: 0.22)) {
            analysisPaneHeight = floorIdeal
        }
    }
}

private struct SplitHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 480
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .frame(width: 800, height: 600)
}
