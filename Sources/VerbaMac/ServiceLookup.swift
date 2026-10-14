import AppKit
import Foundation

/// Bridges macOS Services (“Look Up in VerbaMac”) into the SwiftUI app.
///
/// `Info.plist` declares `NSServices` with `NSMessage` = `lookUpInVerbaMac`.
/// The app delegate is registered as `NSApp.servicesProvider`.
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static weak var shared: AppDelegate?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
        // System may auto-bind ⌘0 to View > Actual Size; ⌘0 is Search > Both.
        Self.stripActualSizeKeyEquivalent()
        Self.installDictionaryFindSubmenu()
        DispatchQueue.main.async {
            Self.stripActualSizeKeyEquivalent()
            Self.installDictionaryFindSubmenu()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Self.stripActualSizeKeyEquivalent()
            Self.installDictionaryFindSubmenu()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            Self.stripActualSizeKeyEquivalent()
            Self.installDictionaryFindSubmenu()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        Self.installDictionaryFindSubmenu()
    }

    /// Clear any key equivalent on View > Actual Size so ⌘0 stays on Search > Both.
    static func stripActualSizeKeyEquivalent() {
        guard let mainMenu = NSApp.mainMenu else { return }
        for top in mainMenu.items {
            guard let submenu = top.submenu else { continue }
            for item in submenu.items where item.title == "Actual Size" {
                if !item.keyEquivalent.isEmpty {
                    item.keyEquivalent = ""
                    item.keyEquivalentModifierMask = []
                }
            }
        }
    }

    /// Dictionary-style Edit > Find submenu (SwiftUI `Menu` inside CommandGroup
    /// flattens on this SDK; install a real NSMenu instead).
    static func installDictionaryFindSubmenu() {
        guard let mainMenu = NSApp.mainMenu else {
            return
        }
        guard let editItem = mainMenu.items.first(where: { $0.title == "Edit" || $0.title.hasPrefix("Edit") }),
              let editMenu = editItem.submenu
        else {
            return
        }
        if let existing = editMenu.items.first(where: { $0.title == "Find" }),
           existing.submenu?.items.contains(where: { $0.title.hasPrefix("Find") }) == true {
            return
        }

        let removeTitles: Set<String> = [
            "Find",
            "Search For a New Word…",
            "Find…",
            "Find Next",
            "Find Previous",
            "Use Selection for Find",
            "Jump to Selection",
        ]
        for item in editMenu.items.reversed() where removeTitles.contains(item.title) {
            let idx = editMenu.index(of: item)
            editMenu.removeItem(item)
            if idx > 0, editMenu.item(at: idx - 1)?.isSeparatorItem == true {
                editMenu.removeItem(at: idx - 1)
            }
        }

        guard let target = AppDelegate.shared else {
            return
        }

        let findMenu = NSMenu(title: "Find")
        let entries: [(String, String, NSEvent.ModifierFlags, Selector)] = [
            ("Search For a New Word…", "f", [.command, .option], NSSelectorFromString("verbaMenuFocusSearch:")),
            ("Find…", "f", [.command], NSSelectorFromString("verbaMenuFindShow:")),
            ("Find Next", "g", [.command], NSSelectorFromString("verbaMenuFindNext:")),
            ("Find Previous", "g", [.command, .shift], NSSelectorFromString("verbaMenuFindPrevious:")),
            ("Use Selection for Find", "e", [.command], NSSelectorFromString("verbaMenuUseSelectionForFind:")),
            ("Jump to Selection", "j", [.command], NSSelectorFromString("verbaMenuJumpToSelection:")),
        ]
        for (idx, entry) in entries.enumerated() {
            if idx == 4 {
                findMenu.addItem(.separator())
            }
            let item = NSMenuItem(title: entry.0, action: entry.3, keyEquivalent: entry.1)
            item.keyEquivalentModifierMask = entry.2
            item.target = target
            findMenu.addItem(item)
        }

        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = findMenu

        if let selectAll = editMenu.items.first(where: { $0.title == "Select All" }),
           let idx = editMenu.items.firstIndex(of: selectAll) {
            editMenu.insertItem(.separator(), at: idx + 1)
            editMenu.insertItem(findItem, at: idx + 2)
        } else {
            editMenu.addItem(.separator())
            editMenu.addItem(findItem)
        }
        editMenu.delegate = target
    }

    /// Re-assert Find when SwiftUI rebuilds Edit just before display.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Edit" || menu.items.contains(where: { $0.title == "Select All" }) else { return }
        // Avoid recursion: only install if Find missing.
        if menu.items.contains(where: { $0.title == "Find" && $0.submenu != nil }) { return }
        AppDelegate.installDictionaryFindSubmenu()
    }


    @objc func verbaMenuFocusSearch(_ sender: Any?) {
        NotificationCenter.default.post(name: .verbaFocusSearch, object: nil)
    }
    @objc func verbaMenuFindShow(_ sender: Any?) {
        NotificationCenter.default.post(name: .verbaFindShow, object: nil)
    }
    @objc func verbaMenuFindNext(_ sender: Any?) {
        NotificationCenter.default.post(name: .verbaFindNext, object: nil)
    }
    @objc func verbaMenuFindPrevious(_ sender: Any?) {
        NotificationCenter.default.post(name: .verbaFindPrevious, object: nil)
    }
    @objc func verbaMenuUseSelectionForFind(_ sender: Any?) {
        NotificationCenter.default.post(name: .verbaUseSelectionForFind, object: nil)
    }
    @objc func verbaMenuJumpToSelection(_ sender: Any?) {
        NotificationCenter.default.post(name: .verbaJumpToSelection, object: nil)
    }

    /// Services entry point — must match Info.plist `NSMessage`.
    @objc func lookUpInVerbaMac(
        _ pboard: NSPasteboard,
        userData: String,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        let types: [NSPasteboard.PasteboardType] = [.string]
        guard pboard.availableType(from: types) != nil,
              let text = pboard.string(forType: .string)
                ?? pboard.readObjects(forClasses: [NSString.self], options: nil)?.first as? String
        else {
            error.pointee = "VerbaMac: no text on the pasteboard." as NSString
            return
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            error.pointee = "VerbaMac: empty selection." as NSString
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .verbaServiceLookup,
                object: trimmed
            )
        }
    }
}

extension Notification.Name {
    static let verbaFocusSearch = Notification.Name("verbaFocusSearch")
    static let verbaServiceLookup = Notification.Name("verbaServiceLookup")
    static let verbaOpenAbout = Notification.Name("verbaOpenAbout")
}
