import SwiftUI
import AppKit

/// Vertical split with a draggable divider, min/max clamps, and programmatic snap.
struct SnappingVSplitView<Top: View, Bottom: View>: View {
    @Binding var topHeight: CGFloat
    /// True while the user is dragging the divider — skips GeometryReader write-backs.
    @Binding var isDragging: Bool
    var minTop: CGFloat = 80
    var minBottom: CGFloat = 160
    /// Cap the analysis pane so the lexicon keeps most of the window.
    /// Slightly higher than before so multi-row parses stay fully visible after snap.
    var maxTopFraction: CGFloat = 0.52

    @ViewBuilder var top: () -> Top
    @ViewBuilder var bottom: () -> Bottom

    /// Local height used while dragging so we don't fight the parent binding / GeometryReader.
    @State private var dragHeight: CGFloat?

    var body: some View {
        GeometryReader { geo in
            let total = geo.size.height
            let maxTop = max(minTop, total * maxTopFraction)
            let upperBound = max(minTop, total - minBottom)
            let source = dragHeight ?? topHeight
            let clamped = min(max(source, minTop), min(maxTop, upperBound))

            VStack(spacing: 0) {
                top()
                    .frame(height: clamped)
                    .frame(maxWidth: .infinity)
                    .clipped()

                SplitDivider(
                    displayedTop: clamped,
                    minTop: minTop,
                    minBottom: minBottom,
                    maxTopFraction: maxTopFraction,
                    totalHeight: total,
                    onDragBegan: {
                        isDragging = true
                        dragHeight = topHeight
                    },
                    onDragChanged: { proposed in
                        let bound = min(max(proposed, minTop), min(maxTop, upperBound))
                        dragHeight = bound
                    },
                    onDragEnded: { final in
                        let bound = min(max(final, minTop), min(maxTop, upperBound))
                        var t = Transaction()
                        t.disablesAnimations = true
                        withTransaction(t) {
                            topHeight = bound
                        }
                        dragHeight = nil
                        isDragging = false
                    }
                )

                bottom()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                guard !isDragging, dragHeight == nil else { return }
                if abs(topHeight - clamped) > 0.5 {
                    topHeight = clamped
                }
            }
            .onChange(of: total) { _, newTotal in
                guard !isDragging, dragHeight == nil else { return }
                let newMax = max(minTop, newTotal * maxTopFraction)
                let newUpper = max(minTop, newTotal - minBottom)
                topHeight = min(max(topHeight, minTop), min(newMax, newUpper))
            }
        }
    }

}

enum AnalysisPaneSizing {
    /// Extra slack so the last analysis row is never clipped under the divider.
    static let snapPadding: CGFloat = 14

    /// Ideal analysis-pane height for `count` rows (snap-after-parse).
    static func idealTopHeight(
        analysisCount: Int,
        availableHeight: CGFloat,
        minTop: CGFloat = 80,
        minBottom: CGFloat = 160,
        maxTopFraction: CGFloat = 0.52
    ) -> CGFloat {
        // Leave generous room so multi-line rows (lemma / morph / quantity) stay visible.
        // Prefer slightly tall over clipped — user should not need to drag down after parse.
        let row: CGFloat = analysisCount == 0 ? 0 : 56
        let chrome: CGFloat = analysisCount == 0 ? 108 : 8
        let content = analysisCount == 0
            ? chrome
            : chrome + CGFloat(analysisCount) * row + snapPadding
        let maxTop = max(minTop, availableHeight * maxTopFraction)
        let upper = max(minTop, availableHeight - minBottom)
        return min(max(content, minTop), min(maxTop, upper))
    }

    static func clampTopHeight(
        _ raw: CGFloat,
        availableHeight: CGFloat,
        minTop: CGFloat = 80,
        minBottom: CGFloat = 160,
        maxTopFraction: CGFloat = 0.52
    ) -> CGFloat {
        let maxTop = max(minTop, availableHeight * maxTopFraction)
        let upper = max(minTop, availableHeight - minBottom)
        return min(max(raw, minTop), min(maxTop, upper))
    }
}

private struct SplitDivider: View {
    let displayedTop: CGFloat
    let minTop: CGFloat
    let minBottom: CGFloat
    let maxTopFraction: CGFloat
    let totalHeight: CGFloat
    let onDragBegan: () -> Void
    let onDragChanged: (CGFloat) -> Void
    let onDragEnded: (CGFloat) -> Void

    @State private var dragStart: CGFloat?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color(nsColor: .separatorColor))
                .frame(height: 1)
            // Wider hit target
            Color.clear
                .frame(height: 8)
                .contentShape(Rectangle())
        }
        .frame(height: 8)
        .padding(.vertical, -3)
        .onHover { hovering in
            if hovering {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragStart == nil {
                        dragStart = displayedTop
                        onDragBegan()
                    }
                    let maxTop = max(minTop, totalHeight * maxTopFraction)
                    let upper = max(minTop, totalHeight - minBottom)
                    let proposed = (dragStart ?? displayedTop) + value.translation.height
                    let bound = min(max(proposed, minTop), min(maxTop, upper))
                    onDragChanged(bound)
                }
                .onEnded { value in
                    let maxTop = max(minTop, totalHeight * maxTopFraction)
                    let upper = max(minTop, totalHeight - minBottom)
                    let proposed = (dragStart ?? displayedTop) + value.translation.height
                    let bound = min(max(proposed, minTop), min(maxTop, upper))
                    dragStart = nil
                    onDragEnded(bound)
                }
        )
        .accessibilityLabel("Pane divider")
        .accessibilityHint("Drag to resize analysis and lexicon panes")
    }
}
