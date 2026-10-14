import SwiftUI
import AppKit

/// Invisible AppKit first-responder that routes ↑/↓/Return/Tab for the analyses pane.
/// SwiftUI `.focusable` + `.onKeyPress` is unreliable on a ScrollView stack.
struct AnalysesKeyboardHost: NSViewRepresentable {
    var isActive: Bool
    var onUp: () -> Void
    var onDown: () -> Void
    var onReturn: () -> Void
    /// Shift-Tab → search (with selection handled by caller).
    var onShiftTab: () -> Void = {}
    /// Plain Tab → lexicon (optional forward cycle).
    var onTab: () -> Void = {}
    /// Called when the host loses first responder (e.g. user clicks the search field).
    var onResign: () -> Void = {}

    func makeNSView(context: Context) -> KeyView {
        let view = KeyView()
        view.onUp = onUp
        view.onDown = onDown
        view.onReturn = onReturn
        view.onShiftTab = onShiftTab
        view.onTab = onTab
        // Transparent; exists only to own firstResponder for key events.
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        return view
    }

    func updateNSView(_ view: KeyView, context: Context) {
        view.onUp = onUp
        view.onDown = onDown
        view.onReturn = onReturn
        view.onShiftTab = onShiftTab
        view.onTab = onTab
        // Grab first responder only on the inactive → active transition. Re-grabbing on
        // every SwiftUI update stole focus back from the search field when it was clicked.
        if isActive && !view.wasActive {
            DispatchQueue.main.async {
                if view.window?.firstResponder !== view { view.window?.makeFirstResponder(view) }
            }
        }
        view.wasActive = isActive
    }

    final class KeyView: NSView {
        var wasActive = false
        var onResign: (() -> Void)?

        override func resignFirstResponder() -> Bool {
            let ok = super.resignFirstResponder()
            if ok { DispatchQueue.main.async { [weak self] in self?.onResign?() } }
            return ok
        }
        var onUp: (() -> Void)?
        var onDown: (() -> Void)?
        var onReturn: (() -> Void)?
        var onShiftTab: (() -> Void)?
        var onTab: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch event.keyCode {
            case 126: // ↑
                onUp?()
            case 125: // ↓
                onDown?()
            case 36, 76: // Return / keypad Enter
                onReturn?()
            case 48: // Tab
                if flags.contains(.shift) {
                    onShiftTab?()
                } else if flags.isEmpty {
                    onTab?()
                } else {
                    super.keyDown(with: event)
                }
            default:
                super.keyDown(with: event)
            }
        }
    }
}
