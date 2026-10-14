import Foundation

/// One morphological analysis of a surface form.
struct Analysis: Identifiable, Hashable, Sendable {
    let id: UUID
    /// Dictionary headword as displayed (may include macrons / accents).
    let lemma: String
    /// Normalized key for lexicon lookup.
    let lemmaNorm: String
    let language: LexiconLanguage
    /// Part of speech label, e.g. "noun", "verb".
    let pos: String
    /// Full morphology string, e.g. "nom./acc./voc. pl."
    let morphology: String
    /// Optional Latin vowel quantity / stem info from Morpheus, or WORDS citation.
    let quantity: String?
    /// Optional secondary English gloss (WORDS). L&S/LSJ remain the definition.
    let gloss: String?
    /// Morpheus homograph number (`abdico#2`) → nth L&S/LSJ row sharing `lemmaNorm`.
    let homograph: Int?
    /// L&S headword this analysis opens (pane label, e.g. ab-dīco or cito²). Set after lookup.
    var headwordLabel: String? = nil

    init(
        id: UUID = UUID(),
        lemma: String,
        lemmaNorm: String,
        language: LexiconLanguage,
        pos: String,
        morphology: String,
        quantity: String? = nil,
        gloss: String? = nil,
        homograph: Int? = nil
    ) {
        self.id = id
        self.lemma = lemma
        self.lemmaNorm = lemmaNorm
        self.language = language
        self.pos = pos
        self.morphology = morphology
        self.quantity = quantity
        self.gloss = gloss
        self.homograph = homograph
    }

    /// Pane label: Latin quantity policy applied, homographs as abdico¹ / abdico² (headword-pane style).
    var displayLemma: String {
        if let headwordLabel { return headwordLabel }
        return HeadwordLabel.make(lemma: lemma, latin: language == .latin, homograph: homograph)
    }

    var summaryLine: String {
        var parts = [lemma]
        if let quantity, !quantity.isEmpty {
            parts.append("(\(quantity))")
        }
        parts.append("—")
        parts.append(pos)
        parts.append(morphology)
        return parts.joined(separator: " ")
    }
}
