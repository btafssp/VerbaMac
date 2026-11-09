import Foundation

/// Collapse analyses that share a lexicon headword (or, failing that, the same
/// lemma) into one row, combining their parses the way Morpheus writes
/// syncretic forms (`neut nom/voc/acc pl`).
enum AnalysisMerger: Sendable {

    static func merge(_ analyses: [Analysis]) -> [Analysis] {
        var order: [GroupKey] = []
        var buckets: [GroupKey: [Analysis]] = [:]
        for analysis in analyses {
            let key = GroupKey(analysis)
            if buckets[key] == nil {
                order.append(key)
                buckets[key] = [analysis]
            } else {
                buckets[key]?.append(analysis)
            }
        }
        return order.map { combine(buckets[$0]!) }
    }

    // MARK: - Key

    private struct GroupKey: Hashable {
        let language: LexiconLanguage
        let identity: String
        let homograph: Int?
        let hasLexiconHeadword: Bool

        init(_ analysis: Analysis) {
            language = analysis.language
            homograph = analysis.homograph
            if let label = analysis.headwordLabel, !label.isEmpty {
                hasLexiconHeadword = true
                // Include the visible label so cito¹ / cito² stay distinct.
                identity = "hw:" + label
            } else {
                hasLexiconHeadword = false
                let norm = analysis.language == .greek
                    ? MorphPreprocess.greekBase(analysis.lemmaNorm)
                    : MorphPreprocess.latinLookupKey(analysis.lemmaNorm)
                identity = "lm:" + norm
            }
        }
    }

    // MARK: - Combine a bucket

    private static func combine(_ items: [Analysis]) -> Analysis {
        precondition(!items.isEmpty)
        guard items.count > 1 else { return items[0] }

        let representative = pickRepresentative(items)
        let morph = MorphologyMerge.combine(items.map(\.morphology))
        let quantities = Set(items.compactMap { $0.quantity }.filter { !$0.isEmpty })
        let quantity = quantities.count == 1 ? quantities.first : representative.quantity
        let gloss = items.first(where: { $0.gloss?.isEmpty == false })?.gloss

        var result = Analysis(
            id: representative.id,
            lemma: representative.lemma,
            lemmaNorm: representative.lemmaNorm,
            language: representative.language,
            pos: representative.pos,
            morphology: morph,
            quantity: quantity,
            gloss: gloss,
            homograph: representative.homograph
        )
        result.headwordLabel = items.first(where: { $0.headwordLabel != nil })?.headwordLabel
        return result
    }

    private static func pickRepresentative(_ items: [Analysis]) -> Analysis {
        if let labeled = items.first(where: { analysis in
            guard let hw = analysis.headwordLabel else { return false }
            let hwKey = MorphPreprocess.latinLookupKey(hw)
            return MorphPreprocess.latinLookupKey(analysis.lemma) == hwKey
                || MorphPreprocess.latinLookupKey(analysis.lemmaNorm) == hwKey
        }) {
            return labeled
        }
        return items[0]
    }
}

/// Combine Morpheus-style morphology strings when they differ only in case.
enum MorphologyMerge: Sendable {
    private static let caseOrder = ["nom", "voc", "acc", "gen", "dat", "abl"]
    private static let caseSet = Set(caseOrder)
    private static let numberSet: Set<String> = ["sg", "pl"]

    static func combine(_ morphs: [String]) -> String {
        var seen = Set<String>()
        let unique = morphs.filter { morph in
            let key = morph.trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        if unique.isEmpty { return morphs.first ?? "" }
        if unique.count == 1 { return unique[0] }

        let parsed = unique.map(parseNominal)
        if parsed.allSatisfy({ $0 != nil }),
           let merged = mergeNominals(parsed.compactMap { $0 }) {
            return merged
        }
        return unique.joined(separator: " · ")
    }

    fileprivate struct Nominal {
        var gender: String?
        var cases: [String]
        var number: String
        var extras: String
    }

    private static func parseNominal(_ raw: String) -> Nominal? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let extraParts = trimmed.components(separatedBy: " · ")
        let main = extraParts[0]
        let extras = extraParts.dropFirst().joined(separator: " · ")
        let tokens = main.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var genderParts: [String] = []
        var cases: [String] = []
        var number: String?
        var leftover: [String] = []

        for token in tokens {
            if number == nil, numberSet.contains(bare(token)) {
                number = bare(token)
                continue
            }
            let splitCases = caseTokens(in: token)
            if !splitCases.isEmpty {
                cases.append(contentsOf: splitCases)
                continue
            }
            if cases.isEmpty, number == nil, looksLikeGender(token) {
                genderParts.append(normalizeGenderToken(token))
                continue
            }
            leftover.append(token)
        }

        guard let number, !cases.isEmpty, leftover.isEmpty else { return nil }
        let gender = genderParts.isEmpty ? nil : genderParts.joined(separator: " ")
        return Nominal(gender: gender, cases: cases, number: number, extras: extras)
    }

    private static func mergeNominals(_ items: [Nominal]) -> String? {
        guard let first = items.first else { return nil }
        let extras = Set(items.map(\.extras))
        let numbers = Set(items.map(\.number))
        guard extras.count == 1, numbers.count == 1 else { return nil }

        let genders = Set(items.compactMap(\.gender))
        if genders.count > 1 { return nil }
        let gender = genders.first

        var seen = Set<String>()
        var ordered: [String] = []
        for name in caseOrder {
            if items.contains(where: { $0.cases.contains(name) }), !seen.contains(name) {
                seen.insert(name)
                ordered.append(name)
            }
        }
        // Preserve any unexpected case token.
        for item in items {
            for name in item.cases where !seen.contains(name) {
                seen.insert(name)
                ordered.append(name)
            }
        }
        guard !ordered.isEmpty else { return nil }

        var parts: [String] = []
        if let gender, !gender.isEmpty { parts.append(gender) }
        parts.append(ordered.joined(separator: "/"))
        parts.append(first.number)
        var result = parts.joined(separator: " ")
        if !first.extras.isEmpty {
            result += " · " + first.extras
        }
        return result
    }

    private static func bare(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet(charactersIn: ".,")).lowercased()
    }

    private static func caseTokens(in token: String) -> [String] {
        let parts = token.split(separator: "/").map { bare(String($0)) }.filter { !$0.isEmpty }
        guard !parts.isEmpty, parts.allSatisfy({ caseSet.contains($0) }) else { return [] }
        return parts
    }

    private static func looksLikeGender(_ token: String) -> Bool {
        let cleaned = token.trimmingCharacters(in: CharacterSet(charactersIn: ","))
        if cleaned == "comm" || cleaned == "comm." { return true }
        if ["ὁ", "ἡ", "τό"].contains(cleaned) { return true }
        let parts = cleaned.split(separator: "/").map(String.init)
        return !parts.isEmpty && parts.allSatisfy { ["masc", "fem", "neut"].contains($0) }
    }

    private static func normalizeGenderToken(_ token: String) -> String {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        if bare(trimmed) == "comm" { return "comm." }
        return trimmed
    }
}
