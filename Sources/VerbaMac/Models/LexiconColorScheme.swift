import Foundation
import SwiftUI

/// Temporary / debug lexicon + analysis pane color schemes.
/// Default is Softer Dark; Appearance menu still offers every scheme including System Default.
enum LexiconColorScheme: String, CaseIterable, Identifiable, Sendable {
    case systemDefault
    case highContrastDark
    case sepiaPaper
    case lightClassic
    case softDark

    var id: String { rawValue }

    static let storageKey = "verba.debugLexiconColorScheme"

    /// App-wide default when nothing is stored yet.
    static let appDefault: LexiconColorScheme = .softDark

    var menuTitle: String {
        switch self {
        case .systemDefault: return "System Default"
        case .highContrastDark: return "High-Contrast Dark"
        case .sepiaPaper: return "Sepia / Paper (Diogenes-like)"
        case .lightClassic: return "Light Classic"
        case .softDark: return "Softer Dark"
        }
    }

    var shortLabel: String {
        switch self {
        case .systemDefault: return "system-default"
        case .highContrastDark: return "high-contrast-dark"
        case .sepiaPaper: return "sepia-paper"
        case .lightClassic: return "light-classic"
        case .softDark: return "soft-dark"
        }
    }

    /// CSS custom properties + html/body overrides for the article chrome.
    var cssVariables: String {
        switch self {
        case .systemDefault:
            return """
            :root { color-scheme: light dark; }
            html, body {
              background: transparent;
              color: CanvasText;
              --muted: GrayText;
              --gloss-weight: 600;
            }
            """
        case .highContrastDark:
            return """
            :root { color-scheme: dark; }
            html, body {
              background: #0b0d10;
              color: #f4f6f8;
              --muted: #b7c0cc;
              --gloss-weight: 700;
            }
            """
        case .sepiaPaper:
            return """
            :root { color-scheme: light; }
            html, body {
              background: #f3e9d5;
              color: #2c241b;
              --muted: #6a5a48;
              --gloss-weight: 700;
            }
            """
        case .lightClassic:
            return """
            :root { color-scheme: light; }
            html, body {
              background: #fafafa;
              color: #1a1a1a;
              --muted: #5c5c5c;
              --gloss-weight: 600;
            }
            """
        case .softDark:
            return """
            :root { color-scheme: dark; }
            html, body {
              background: #2a2e36;
              color: #e8eaed;
              --muted: #a8b0bd;
              --gloss-weight: 600;
            }
            """
        }
    }

    // MARK: - Shared SwiftUI tokens (analyses pane matches lexicon)

    /// Pane backdrop — same hex as lexicon CSS / ArticleView for non-system schemes.
    var paneBackground: Color {
        switch self {
        case .systemDefault:
            return Color(nsColor: .windowBackgroundColor)
        case .highContrastDark:
            return Color(red: 0.043, green: 0.051, blue: 0.063) // #0b0d10
        case .sepiaPaper:
            return Color(red: 0.953, green: 0.914, blue: 0.835) // #f3e9d5
        case .lightClassic:
            return Color(red: 0.980, green: 0.980, blue: 0.980) // #fafafa
        case .softDark:
            return Color(red: 0.165, green: 0.180, blue: 0.212) // #2a2e36
        }
    }

    var primaryText: Color {
        switch self {
        case .systemDefault:
            return Color.primary
        case .highContrastDark:
            return Color(red: 0.957, green: 0.965, blue: 0.973) // #f4f6f8
        case .sepiaPaper:
            return Color(red: 0.173, green: 0.141, blue: 0.106) // #2c241b
        case .lightClassic:
            return Color(red: 0.102, green: 0.102, blue: 0.102) // #1a1a1a
        case .softDark:
            return Color(red: 0.910, green: 0.918, blue: 0.929) // #e8eaed
        }
    }

    var mutedText: Color {
        switch self {
        case .systemDefault:
            return Color.secondary
        case .highContrastDark:
            return Color(red: 0.718, green: 0.753, blue: 0.800) // #b7c0cc
        case .sepiaPaper:
            return Color(red: 0.416, green: 0.353, blue: 0.282) // #6a5a48
        case .lightClassic:
            return Color(red: 0.361, green: 0.361, blue: 0.361) // #5c5c5c
        case .softDark:
            return Color(red: 0.659, green: 0.690, blue: 0.741) // #a8b0bd
        }
    }

    var tertiaryText: Color {
        switch self {
        case .systemDefault:
            return Color.secondary.opacity(0.7)
        default:
            return mutedText.opacity(0.78)
        }
    }

    /// Alternating row wash on the analyses list.
    var rowStripe: Color {
        switch self {
        case .systemDefault:
            return Color.primary.opacity(0.04)
        case .highContrastDark, .softDark:
            return Color.white.opacity(0.05)
        case .sepiaPaper, .lightClassic:
            return Color.black.opacity(0.04)
        }
    }

    var badgeFill: Color {
        switch self {
        case .systemDefault:
            return Color(nsColor: .quaternaryLabelColor).opacity(0.35)
        case .highContrastDark, .softDark:
            return Color.white.opacity(0.10)
        case .sepiaPaper, .lightClassic:
            return Color.black.opacity(0.08)
        }
    }

    var selectionFill: Color {
        switch self {
        case .systemDefault:
            return Color.accentColor.opacity(0.18)
        case .highContrastDark, .softDark:
            return Color.accentColor.opacity(0.28)
        case .sepiaPaper, .lightClassic:
            return Color.accentColor.opacity(0.16)
        }
    }

    static func stored() -> LexiconColorScheme {
        let raw = UserDefaults.standard.string(forKey: storageKey) ?? appDefault.rawValue
        return LexiconColorScheme(rawValue: raw) ?? .appDefault
    }

    static func setStored(_ scheme: LexiconColorScheme) {
        UserDefaults.standard.set(scheme.rawValue, forKey: storageKey)
        NotificationCenter.default.post(name: .verbaLexiconColorSchemeChanged, object: scheme.rawValue)
    }
}

extension Notification.Name {
    static let verbaLexiconColorSchemeChanged = Notification.Name("verbaLexiconColorSchemeChanged")
}
