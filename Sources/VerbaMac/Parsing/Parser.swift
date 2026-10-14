import Foundation

/// Morphological parser: surface form → analyses.
///
/// Implementations (Morpheus, WORDS) run off the main actor.
/// Callers should dispatch to a background queue / task.
protocol Parser: Sendable {
    /// Parse a query string for the given language filter.
    /// - Parameters:
    ///   - query: Raw user input (will be trimmed / normalized by the implementation).
    ///   - language: Latin, Greek, or Both.
    /// - Returns: Zero or more analyses; empty means no hit (show empty state).
    func parse(_ query: String, language: Language) async -> [Analysis]
}
