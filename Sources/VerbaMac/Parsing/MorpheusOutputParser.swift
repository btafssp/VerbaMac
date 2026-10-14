import Foundation

/// Parses Perseus-format Morpheus / `cruncher` stdout into `[Analysis]`.
///
/// Typical lines:
/// ```
/// cactus
/// <NL>N cactus  masc nom sg			us_i</NL>
/// <NL>N a)nqrw/pou,a)/nqrwpos  masc gen sg			os_ou</NL>
/// <NL>V a_)nqrwpou=,a)nqrwpo/omai  imperf ind mp 2nd sg	doric aeolic	contr	ow_pr,ow_denom</NL>
/// ```
enum MorpheusOutputParser: Sendable {

    private static let nlRegex: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"<NL>(.*?)</NL>"#, options: [.dotMatchesLineSeparators])
    }()

    static func parse(
        stdout: String,
        language: LexiconLanguage,
        surfaceForm: String
    ) -> [Analysis] {
        var analyses: [Analysis] = []
        let ns = stdout as NSString
        let full = NSRange(location: 0, length: ns.length)

        nlRegex.enumerateMatches(in: stdout, options: [], range: full) { match, _, _ in
            guard let match, match.numberOfRanges >= 2,
                  let range = Range(match.range(at: 1), in: stdout) else { return }
            let inner = String(stdout[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let analysis = parseNLBody(inner, language: language, surfaceForm: surfaceForm) {
                analyses.append(analysis)
            }
        }

        if analyses.isEmpty {
            for line in stdout.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let first = trimmed.first, first.isLetter, first.isUppercase else { continue }
                if let analysis = parseNLBody(trimmed, language: language, surfaceForm: surfaceForm) {
                    analyses.append(analysis)
                }
            }
        }

        return analyses
    }

    // MARK: - One <NL> body

    private static func parseNLBody(
        _ body: String,
        language: LexiconLanguage,
        surfaceForm: String
    ) -> Analysis? {
        guard let posEnd = body.firstIndex(where: { $0.isWhitespace }) else { return nil }
        let posCode = String(body[..<posEnd])
        guard let first = posCode.first, first.isLetter else { return nil }

        let rest = body[posEnd...].trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { return nil }

        let fieldSplit = splitLemmaAndMorph(rest)
        let lemmaField = fieldSplit.lemmaField
        let morphAndStem = fieldSplit.remainder

        let formOrLemma: String?
        var lemmaBeta: String
        if let comma = lemmaField.firstIndex(of: ",") {
            formOrLemma = String(lemmaField[..<comma])
            lemmaBeta = String(lemmaField[lemmaField.index(after: comma)...])
        } else {
            formOrLemma = nil
            lemmaBeta = lemmaField
        }

        // Morpheus homograph suffix (`abdico#1`, `abdico#2`): keep the number, never display `#`.
        var homograph: Int? = nil
        if let hash = lemmaBeta.lastIndex(of: "#"), let n = Int(lemmaBeta[lemmaBeta.index(after: hash)...]) {
            homograph = n
            lemmaBeta = String(lemmaBeta[..<hash])
        }

        let (morphology, stemType, extras) = splitMorphAndStem(morphAndStem)
        var pos = expandPOS(posCode)
        // Morpheus files indeclinables under N with the real class as the stem tag
        // ("N cito indeclform adverb", "N o( … article"): show that class, not "noun".
        let posTags: [String: String] = ["adverb": "adverb", "article": "article", "conj": "conjunction",
                                         "exclam": "exclamation", "prep": "preposition", "particle": "particle",
                                         "pron": "pronoun", "numeral": "numeral", "interj": "interjection"]
        if posCode.uppercased() == "N",
           let tag = morphAndStem.split(whereSeparator: { $0 == "\t" || $0 == " " }).last.map(String.init),
           let mapped = posTags[tag] {
            pos = mapped
        }

        let displayLemma: String
        let lemmaNorm: String
        let quantity: String?

        switch language {
        case .greek:
            displayLemma = BetaCode.toDisplay(lemmaBeta)
            lemmaNorm = MorphPreprocess.greekBase(displayLemma)
            quantity = nil  // user decision: hide Morpheus stemtype/derivation codes (aw_pr, os_ou, …)
            _ = stemType
        case .latin:
            // Latin cruncher output is Latin ASCII (+ `_` quantity), not Greek Beta Code.
            displayLemma = BetaCode.latinToDisplay(lemmaBeta)
            lemmaNorm = MorphPreprocess.latinLookupKey(displayLemma)
            // Quantity caption: macronized lemma/form only — never Morpheus stem codes (us_i, s_dis).
            if let formOrLemma, formOrLemma.contains("_") {
                quantity = BetaCode.latinToDisplay(formOrLemma)
            } else if lemmaBeta.contains("_") {
                quantity = displayLemma
            } else {
                quantity = nil
            }
            _ = stemType
        }

        // User decision: never display Morpheus's internal `indeclform` tag.
        let dropTags: Set<String> = ["indeclform"]
        let clean: (String) -> String = { s in
            s.split(separator: " ").filter { !dropTags.contains(String($0)) }
                .map { $0 == "contr" ? "contr." : String($0) }  // user decision: show as "contr."
                .joined(separator: " ")
        }
        let morphShown = clean(morphology)
        let extrasShown = extras.map(clean).filter { !$0.isEmpty }
        var morphParts: [String] = []
        if !morphShown.isEmpty { morphParts.append(morphShown) }
        if !extrasShown.isEmpty { morphParts.append(extrasShown.joined(separator: " ")) }
        let morphString = morphParts.joined(separator: " · ")

        _ = surfaceForm
        _ = formOrLemma

        return Analysis(
            lemma: displayLemma,
            lemmaNorm: lemmaNorm,
            language: language,
            pos: pos,
            morphology: morphString,  // never show the raw Morpheus POS code ("N")
            quantity: quantity,
            homograph: homograph
        )
    }

    private static func splitLemmaAndMorph(_ rest: String) -> (lemmaField: String, remainder: String) {
        let scalars = Array(rest)
        var i = 0
        while i < scalars.count {
            if scalars[i] == "\t" {
                let lemma = String(scalars[..<i]).trimmingCharacters(in: .whitespaces)
                let rem = String(scalars[i...]).trimmingCharacters(in: .whitespaces)
                return (lemma, rem)
            }
            if scalars[i] == " " {
                var j = i
                while j < scalars.count && scalars[j] == " " { j += 1 }
                if j - i >= 2 {
                    let lemma = String(scalars[..<i])
                    let rem = String(scalars[j...]).trimmingCharacters(in: .whitespaces)
                    return (lemma, rem)
                }
            }
            i += 1
        }
        if let sp = rest.firstIndex(where: { $0.isWhitespace }) {
            return (
                String(rest[..<sp]),
                rest[sp...].trimmingCharacters(in: .whitespaces)
            )
        }
        return (rest, "")
    }

    private static func splitMorphAndStem(_ s: String) -> (morph: String, stem: String?, extras: [String]) {
        let tabParts = s.split(separator: "\t", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }

        if tabParts.count >= 2 {
            let morph = tabParts[0]
            let trailing = tabParts.dropFirst().filter { !$0.isEmpty }
            if let last = trailing.last {
                let extras = Array(trailing.dropLast()).filter { !$0.isEmpty }
                return (morph, last, extras)
            }
            return (morph, nil, [])
        }

        let tokens = s.split(whereSeparator: \.isWhitespace).map(String.init)
        if let last = tokens.last, last.contains("_"), tokens.count > 1 {
            let morph = tokens.dropLast().joined(separator: " ")
            return (morph, last, [])
        }
        return (s.trimmingCharacters(in: .whitespaces), nil, [])
    }

    private static func expandPOS(_ code: String) -> String {
        switch code.uppercased() {
        case "N": return "noun"
        case "V": return "verb"
        case "A", "ADJ": return "adjective"
        case "D", "ADV": return "adverb"
        case "P": return "participle"   // Morpheus P = participle (lu/wn, cito_ from cieo)
        case "PRON": return "pronoun"
        case "C", "CONJ": return "conjunction"
        case "R", "PREP": return "preposition"
        case "X", "PART": return "particle"
        case "I", "INTJ": return "interjection"
        case "M", "NUM": return "numeral"
        case "E", "EXCL": return "exclamation"
        default: return code.lowercased()
        }
    }
}
