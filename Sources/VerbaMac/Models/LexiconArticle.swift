import Foundation

/// A lexicon article ready for display.
struct LexiconArticle: Identifiable, Hashable, Sendable {
    let id: UUID
    let lemma: String
    let lemmaNorm: String
    let language: LexiconLanguage
    /// Compact HTML body for the article pane.
    let html: String
    /// Optional plaintext for FTS / accessibility.
    let plain: String?

    init(
        id: UUID = UUID(),
        lemma: String,
        lemmaNorm: String,
        language: LexiconLanguage,
        html: String,
        plain: String? = nil
    ) {
        self.id = id
        self.lemma = lemma
        self.lemmaNorm = lemmaNorm
        self.language = language
        self.html = html
        self.plain = plain
    }
}
