import Foundation

/// User preferences that affect parser invocation .
struct ParserPreferences: Sendable, Equatable {
    /// Greek: pass `-n` to cruncher (ignore accents).
    var greekIgnoreAccents: Bool = true

    static let `default` = ParserPreferences()
}
