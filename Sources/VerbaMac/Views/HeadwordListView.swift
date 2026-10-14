import SwiftUI

/// Dictionary-style leftmost pane: selected lexicon headwords with live prefix match.
struct HeadwordListView: View {
    @ObservedObject var state: AppState
    var colorScheme: LexiconColorScheme = .appDefault
    var contentTextSize: Double = ContentTextSize.defaultPoints
    var keyboardActive: Bool = false
    var onKeyboardResigned: () -> Void = {}
    var onActivate: () -> Void = {}
    var onShiftTab: () -> Void = {}
    var onTab: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Headwords")
                    .font(.system(size: ContentTextSize.captionSize(contentTextSize), weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if state.isUpdatingHeadwords {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            if state.headwords.isEmpty {
                VStack(spacing: 6) {
                    Text(emptyMessage)
                        .font(.system(size: ContentTextSize.captionSize(contentTextSize)))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(12)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.headwords) { hit in
                                Button {
                                    state.selectHeadword(hit)
                                } label: {
                                    Text(hit.displayLemma)
                                        .font(.system(size: ContentTextSize.lemmaSize(contentTextSize)))
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(rowBackground(for: hit))
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(hit.id)
                                .help(hit.lemmaNorm)
                            }
                        }
                    }
                    .onChange(of: state.selectedHeadwordID) { _, id in
                        guard let id else { return }
                        withAnimation(.easeInOut(duration: 0.12)) {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(colorScheme.paneBackground)
        .background(
            // Same transition-only first-responder host as the analyses pane.
            AnalysesKeyboardHost(
                isActive: keyboardActive && !state.headwords.isEmpty,
                onUp: { state.moveHeadwordSelection(by: -1) },
                onDown: { state.moveHeadwordSelection(by: 1) },
                onReturn: { state.openSelectedHeadword() },
                onShiftTab: onShiftTab,
                onTab: onTab,
                onResign: onKeyboardResigned
            )
            .allowsHitTesting(false)
        )
    }

    private func rowBackground(for hit: HeadwordHit) -> Color {
        state.selectedHeadwordID == hit.id
            ? Color.accentColor.opacity(keyboardActive ? 0.45 : 0.28)
            : Color.clear
    }

    private var emptyMessage: String {
        let q = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return "Type to list dictionary headwords." }
        let greek = state.language == .greek
            || (state.language == .both && MorphPreprocess.looksGreek(q))
        return greek ? "No Greek headwords match" : "No Latin headwords match"
    }
}
