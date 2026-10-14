import Foundation

/// Lexicon / parser language selection.
enum Language: String, CaseIterable, Identifiable, Sendable {
    case latin = "lat"
    case greek = "grc"
    case both = "both"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .latin: return "Latin"
        case .greek: return "Greek"
        case .both:  return "Both"
        }
    }

    /// Narrow to a concrete lexicon language, or `nil` when `.both`.
    var concrete: Language? {
        switch self {
        case .latin, .greek: return self
        case .both: return nil
        }
    }
}

/// Concrete language for a single analysis / article (never `.both`).
enum LexiconLanguage: String, CaseIterable, Sendable, Codable, Hashable {
    case latin = "lat"
    case greek = "grc"

    var displayName: String {
        switch self {
        case .latin: return "Latin"
        case .greek: return "Greek"
        }
    }
}
