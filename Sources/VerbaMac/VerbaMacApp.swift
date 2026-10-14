import SwiftUI
import AppKit

@main
struct VerbaMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Each window gets its own `AppState` via `WindowRoot`.
        WindowGroup {
            WindowRoot()
        }
        .defaultSize(width: 980, height: 640)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About VerbaMac…") {
                    NotificationCenter.default.post(name: .verbaOpenAbout, object: nil)
                }
            }

            // Single File > New Window ⌘N (replace system newItem to avoid duplicates).
            CommandGroup(replacing: .newItem) {
                Button("New Window") {
                    NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
                    if let url = URL(string: "verbamac://new") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            // Edit > Find: AppDelegate installs Dictionary-style submenu; also register
            // flat commands so key equivalents stay wired if the submenu is rebuilt.
            CommandGroup(after: .textEditing) {
                Button("Search For a New Word…") {
                    NotificationCenter.default.post(name: .verbaFocusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .option])

                Button("Find…") {
                    NotificationCenter.default.post(name: .verbaFindShow, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)

                Button("Find Next") {
                    NotificationCenter.default.post(name: .verbaFindNext, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Find Previous") {
                    NotificationCenter.default.post(name: .verbaFindPrevious, object: nil)
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])

                Button("Use Selection for Find") {
                    NotificationCenter.default.post(name: .verbaUseSelectionForFind, object: nil)
                }
                .keyboardShortcut("e", modifiers: .command)

                Button("Jump to Selection") {
                    NotificationCenter.default.post(name: .verbaJumpToSelection, object: nil)
                }
                .keyboardShortcut("j", modifiers: .command)
            }

            // Dictionary-style Go menu (was under Edit).
            CommandMenu("Go") {
                Button("Back") {
                    NotificationCenter.default.post(name: .verbaHistoryBack, object: nil)
                }
                .keyboardShortcut("[", modifiers: .command)

                Button("Forward") {
                    NotificationCenter.default.post(name: .verbaHistoryForward, object: nil)
                }
                .keyboardShortcut("]", modifiers: .command)
            }

            // Dictionary-style Search menu (replaces Language).
            // Both ≅ All Dictionaries ⌘0; Latin/Greek ≅ dict slots ⌘1/⌘2.
            CommandMenu("Search") {
                Button("Both") {
                    NotificationCenter.default.post(name: .verbaSetLanguage, object: Language.both.rawValue)
                }
                .keyboardShortcut("0", modifiers: .command)

                Button("Latin") {
                    NotificationCenter.default.post(name: .verbaSetLanguage, object: Language.latin.rawValue)
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Greek") {
                    NotificationCenter.default.post(name: .verbaSetLanguage, object: Language.greek.rawValue)
                }
                .keyboardShortcut("2", modifiers: .command)

                Divider()

                Button("Select Next Language") {
                    NotificationCenter.default.post(name: .verbaSelectNextLanguage, object: nil)
                }
                .keyboardShortcut("}", modifiers: .command)

                Button("Select Previous Language") {
                    NotificationCenter.default.post(name: .verbaSelectPreviousLanguage, object: nil)
                }
                .keyboardShortcut("{", modifiers: .command)
            }

            // Content zoom (analyses + lexicon article). Keep Bigger/Smaller;
            // Actual Size has no ⌘0 (⌘0 is Both / All) — AppDelegate strips any
            // system-assigned ⌘0 on the "Actual Size" title.
            CommandGroup(after: .sidebar) {
                Button("Make Text Bigger") {
                    ContentTextSize.increase()
                }
                .keyboardShortcut("=", modifiers: .command)
                .disabled(!ContentTextSize.canIncrease)

                Button("Make Text Smaller") {
                    ContentTextSize.decrease()
                }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(!ContentTextSize.canDecrease)

                Button("Actual Size") {
                    ContentTextSize.reset()
                }
            }

            // Temporary debug picker — default is Softer Dark; all schemes remain available.
            CommandMenu("Appearance") {
                ForEach(LexiconColorScheme.allCases) { scheme in
                    Button(scheme.menuTitle) {
                        LexiconColorScheme.setStored(scheme)
                    }
                }
                Divider()
                Text("Lexicon article colors (debug)")
            }
        }
    }
}

extension Notification.Name {
    static let verbaHistoryBack = Notification.Name("verbaHistoryBack")
    static let verbaHistoryForward = Notification.Name("verbaHistoryForward")
    static let verbaSetLanguage = Notification.Name("verbaSetLanguage")
    static let verbaSelectNextLanguage = Notification.Name("verbaSelectNextLanguage")
    static let verbaSelectPreviousLanguage = Notification.Name("verbaSelectPreviousLanguage")
    static let verbaFindShow = Notification.Name("verbaFindShow")
    static let verbaFindNext = Notification.Name("verbaFindNext")
    static let verbaFindPrevious = Notification.Name("verbaFindPrevious")
    static let verbaUseSelectionForFind = Notification.Name("verbaUseSelectionForFind")
    static let verbaJumpToSelection = Notification.Name("verbaJumpToSelection")
}

/// Per-window root: independent `AppState`, Services + history notifications.
struct WindowRoot: View {
    @StateObject private var appState = AppState()
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        ContentView()
            .environmentObject(appState)
            .modifier(WindowRootNotifications(
                appState: appState,
                controlActiveState: controlActiveState
            ))
    }
}

/// Splits notification wiring out of `WindowRoot.body` so the type-checker stays happy.
private struct WindowRootNotifications: ViewModifier {
    @ObservedObject var appState: AppState
    var controlActiveState: ControlActiveState

    func body(content: Content) -> some View {
        content
            .modifier(CoreWindowNotifications(appState: appState, controlActiveState: controlActiveState))
            .modifier(FindWindowNotifications(appState: appState, controlActiveState: controlActiveState))
    }
}

private struct CoreWindowNotifications: ViewModifier {
    @ObservedObject var appState: AppState
    var controlActiveState: ControlActiveState

    private var isKeyOrActive: Bool {
        controlActiveState == .key || controlActiveState == .active
    }

    private var isKey: Bool { controlActiveState == .key }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .verbaServiceLookup)) { note in
                guard isKeyOrActive, let q = note.object as? String else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.lookUp(q) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaOpenAbout)) { _ in
                guard isKeyOrActive else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.showAbout = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaHistoryBack)) { _ in
                guard isKey else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.goBack() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaHistoryForward)) { _ in
                guard isKey else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.goForward() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaFocusSearch)) { _ in
                // ContentView listens; key-window gate only.
                _ = isKey
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaSetLanguage)) { note in
                guard isKey, let raw = note.object as? String, let lang = Language(rawValue: raw) else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.setLanguage(lang) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaSelectNextLanguage)) { _ in
                guard isKey else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.selectNextLanguage() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaSelectPreviousLanguage)) { _ in
                guard isKey else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.selectPreviousLanguage() }
            }
    }
}

private struct FindWindowNotifications: ViewModifier {
    @ObservedObject var appState: AppState
    var controlActiveState: ControlActiveState

    private var isKey: Bool { controlActiveState == .key }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .verbaFindShow)) { _ in
                guard isKey else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.showArticleFind() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaFindNext)) { _ in
                guard isKey else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.findNextInArticle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaFindPrevious)) { _ in
                guard isKey else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.findPreviousInArticle() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaUseSelectionForFind)) { _ in
                guard isKey else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.useSelectionForFind() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .verbaJumpToSelection)) { _ in
                guard isKey else { return }
                // Defer: menu notifications can arrive mid view-update.
                DispatchQueue.main.async { appState.jumpToSelectionInArticle() }
            }
    }
}
