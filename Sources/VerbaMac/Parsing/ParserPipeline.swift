import Foundation

/// Tries Morpheus first; on empty / unavailable Latin results, tries Whitaker’s
/// WORDS; otherwise returns no analyses.
///
/// `lastDebugNote` explains which path ran (for status / About debugging).
final class ParserPipeline: Parser, @unchecked Sendable {
    let morpheus: MorpheusParser
    let words: WordsParser

    /// Set after each `parse` — safe to read from MainActor for status UI.
    private let lock = NSLock()
    private var _lastDebugNote: String = ""
    var lastDebugNote: String {
        lock.lock(); defer { lock.unlock() }
        return _lastDebugNote
    }

    init(
        preferences: ParserPreferences = .default,
        morpheus: MorpheusParser? = nil,
        words: WordsParser = WordsParser()
    ) {
        self.morpheus = morpheus ?? MorpheusParser(preferences: preferences)
        self.words = words
    }

    func parse(_ query: String, language: Language) async -> [Analysis] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            setNote("")
            return []
        }

        // --- Morpheus (primary) ---
        if morpheus.isAvailable {
            let results = await morpheus.parse(trimmed, language: language)
            if !results.isEmpty {
                setNote("Morpheus")
                return results
            }
            // Empty Morpheus → continue to WORDS.
        }

        // --- WORDS (Latin only) ---
        let wantsLatin: Bool = {
            switch language {
            case .latin: return true
            case .greek: return false
            case .both: return !MorphPreprocess.looksGreek(trimmed)
            }
        }()

        if wantsLatin {
            let wordsHits = await words.parse(trimmed, language: .latin)
            if !wordsHits.isEmpty {
                let via = "WORDS"
                if morpheus.isAvailable {
                    setNote("\(via) (Morpheus returned no analyses)")
                } else {
                    setNote("\(via) — \(morpheus.availabilityNote)")
                }
                return wordsHits
            }
        }

        if morpheus.isAvailable {
            setNote("Morpheus (no analyses); WORDS no hit")
        } else {
            setNote(morpheus.availabilityNote)
        }
        return []
    }

    private func setNote(_ s: String) {
        lock.lock(); _lastDebugNote = s; lock.unlock()
    }
}

extension ParserPipeline {
    /// User decision 2026-10-13: analyses whose lemma is the typed word itself
    /// (accent/quantity-insensitive, homograph number ignored) come first; all others keep
    /// their order. cito → cito (adv.), cito (verb), then the cieo participles.
    static func exactLemmaFirst(_ analyses: [Analysis], query: String) -> [Analysis] {
        func key(_ s: String, _ lang: LexiconLanguage) -> String {
            lang == .greek ? MorphPreprocess.greekBase(s) : MorphPreprocess.latinLookupKey(s)
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = analyses.filter { key($0.lemma, $0.language) == key(q, $0.language) }
        guard !exact.isEmpty, exact.count < analyses.count else { return analyses }
        let ids = Set(exact.map(\.id))
        return exact + analyses.filter { !ids.contains($0.id) }
    }
}
