import Foundation

/// One dictionary headword row for the left pane (prefix match against `lemma_norm`).
struct HeadwordHit: Identifiable, Hashable, Sendable {
    let lemma: String
    let lemmaNorm: String
    let language: LexiconLanguage
    /// SQLite `articles.id` when known — LSJ homographs share `lemma_norm` (εἰμί / εἶμι).
    var rowID: Int64? = nil
    /// 1-based homograph number in lexicon (id) order; nil when the headword is unique.
    var homographNumber: Int? = nil

    /// Pane label: λογάς¹, λογάς² for homographs; plain lemma otherwise.
    var displayLemma: String {
        HeadwordLabel.make(lemma: lemma, latin: language == .latin, homograph: homographNumber)
    }

    var id: String {
        if let rowID { return "\(language.rawValue):\(lemmaNorm)#\(rowID)" }
        return "\(language.rawValue):\(lemmaNorm)"
    }
}

/// Shared headword-pane label: Latin quantity display policy + superscript homograph number.
enum HeadwordLabel {
    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
        "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
    ]

    static func make(lemma: String, latin: Bool, homograph: Int?) -> String {
        let base = latin ? LatinQuantity.display(lemma) : lemma
        guard let n = homograph else { return base }
        return base + String(String(n).map { superscripts[$0] ?? $0 })
    }
}
