import SwiftUI

/// Intrinsic height of analysis content (empty chrome or row stack).
struct AnalysisContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct AnalysisListView: View {
    @ObservedObject var state: AppState
    /// Shared with lexicon so both panes read as one Appearance theme.
    var colorScheme: LexiconColorScheme = .appDefault
    /// Body base points (same preference as lexicon article).
    var contentTextSize: Double = ContentTextSize.defaultPoints
    var analysesKeyboardActive: Bool = false
    var onKeyboardResigned: () -> Void = {}
    var onActivateAnalyses: () -> Void = {}
    var onTransferToLexicon: () -> Void = {}
    var onTransferToSearch: () -> Void = {}

    var body: some View {
        Group {
            if state.analyses.isEmpty {
                emptyState
            } else {
                analysisStack
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(colorScheme.paneBackground)
        .background(
            AnalysesKeyboardHost(
                isActive: analysesKeyboardActive && !state.analyses.isEmpty,
                onUp: { state.selectPreviousAnalysis() },
                onDown: { state.selectNextAnalysis() },
                onReturn: {
                    guard !state.analyses.isEmpty else { return }
                    onTransferToLexicon()
                },
                onShiftTab: { onTransferToSearch() },
                onTab: {
                    guard !state.analyses.isEmpty else { return }
                    onTransferToLexicon()
                },
                onResign: onKeyboardResigned
            )
            .allowsHitTesting(false)
        )
    }

    /// Non-List stack so we can measure intrinsic height and snap the divider flush.
    private var analysisStack: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(state.analyses.enumerated()), id: \.element.id) { index, analysis in
                        AnalysisRow(
                            analysis: analysis,
                            colorScheme: colorScheme,
                            contentTextSize: contentTextSize
                        )
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(rowBackground(for: analysis, index: index))
                            .contentShape(Rectangle())
                            .id(analysis.id)
                            .onTapGesture {
                                state.selectAnalysis(analysis)
                                onActivateAnalyses()
                            }
                    }
                }
                // Intrinsic height only — do not stretch to fill the ScrollView viewport
                // (that would inflate the preference and leave a gap under the rows).
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: AnalysisContentHeightKey.self,
                            value: geo.size.height + 10 // breathing room above divider (avoid clip)
                        )
                    }
                )
            }
            .scrollIndicators(.automatic)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(colorScheme.paneBackground)
            .onChange(of: state.selectedAnalysisID) {
                guard let id = state.selectedAnalysisID else { return }
                withAnimation(.easeInOut(duration: 0.12)) {
                    proxy.scrollTo(id, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func rowBackground(for analysis: Analysis, index: Int) -> some View {
        let selected = state.selectedAnalysisID == analysis.id
        if selected {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colorScheme.selectionFill)
                .padding(.horizontal, 4)
        } else if index % 2 == 1 {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(colorScheme.rowStripe)
                .padding(.horizontal, 4)
        } else {
            Color.clear
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: ContentTextSize.emptyIconSize(contentTextSize)))
                .foregroundStyle(colorScheme.mutedText)
            Text("No analyses")
                .font(.system(size: ContentTextSize.headlineSize(contentTextSize), weight: .semibold))
                .foregroundStyle(colorScheme.primaryText)
            Text("Try custodes, amo, or λόγος")
                .font(.system(size: ContentTextSize.subheadlineSize(contentTextSize)))
                .foregroundStyle(colorScheme.mutedText)
            if let status = state.statusMessage {
                Text(status)
                    .font(.system(size: ContentTextSize.captionSize(contentTextSize)))
                    .foregroundStyle(colorScheme.tertiaryText)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: AnalysisContentHeightKey.self,
                    value: geo.size.height
                )
            }
        )
    }
}

private struct AnalysisRow: View {
    let analysis: Analysis
    let colorScheme: LexiconColorScheme
    var contentTextSize: Double = ContentTextSize.defaultPoints

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline) {
                Text(analysis.displayLemma)
                    .font(.system(size: ContentTextSize.lemmaSize(contentTextSize), weight: .semibold))
                    .foregroundStyle(colorScheme.primaryText)
                Text(analysis.language.displayName)
                    .font(.system(size: ContentTextSize.captionSize(contentTextSize)))
                    .foregroundStyle(colorScheme.primaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(colorScheme.badgeFill, in: Capsule())
                Spacer(minLength: 8)
                Text(analysis.pos)
                    .font(.system(size: ContentTextSize.captionSize(contentTextSize)))
                    .foregroundStyle(colorScheme.mutedText)
            }
            Text(analysis.morphology)
                .font(.system(size: ContentTextSize.morphologySize(contentTextSize)))
                .foregroundStyle(colorScheme.mutedText)
            if let quantity = analysis.quantity {
                Text(analysis.language == .latin ? LatinQuantity.display(quantity) : quantity)
                    .font(.system(size: ContentTextSize.captionSize(contentTextSize)))
                    .foregroundStyle(colorScheme.tertiaryText)
            }
        }
    }
}
