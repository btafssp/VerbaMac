import Foundation

/// Parses classic Whitaker’s WORDS console text into `[Analysis]`.
///
/// Typical block (Ada WORDS / many ports):
/// ```
/// cu.stodes             N      3 1 NOM P M
/// custos, custodis  N (3rd) M   [XXXAX]
/// guard, protector, guardian; attendant, watchman;
/// ```
///
/// Gloss lines are stored on `Analysis.gloss` (secondary). L&S remains the
/// definition via `LexiconStore`. Does **not** handle Greek.
enum WordsOutputParser: Sendable {

    /// Parse WORDS stdout for a Latin surface form.
    static func parse(stdout: String, surfaceForm: String) -> [Analysis] {
        let lines = stdout
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        var results: [Analysis] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            // Morphology / form line: contains case or tense codes, or starts with stem.ending
            if let morphHit = parseMorphLine(line) {
                var lemma = MorphPreprocess.latinLookupKey(surfaceForm)
                var lemmaDisplay = surfaceForm
                var pos = morphHit.pos
                var citation: String?
                var glossParts: [String] = []

                var j = i + 1
                while j < lines.count {
                    let next = lines[j]
                    if looksLikeMorphLine(next) { break }
                    if let dict = parseDictLine(next) {
                        lemmaDisplay = dict.lemma
                        lemma = MorphPreprocess.latinLookupKey(dict.lemmaNorm)
                        pos = dict.pos.isEmpty ? pos : dict.pos
                        citation = dict.citation
                    } else if looksLikeGloss(next) {
                        glossParts.append(next.trimmingCharacters(in: CharacterSet(charactersIn: "|")))
                    } else if next.hasPrefix("=>") || next.hasPrefix("*") {
                        break
                    }
                    j += 1
                }

                let gloss = glossParts.isEmpty ? nil : glossParts.joined(separator: " ")
                results.append(
                    Analysis(
                        lemma: lemmaDisplay,
                        lemmaNorm: lemma,
                        language: .latin,
                        pos: pos,
                        morphology: morphHit.morphology,
                        quantity: citation,
                        gloss: gloss
                    )
                )
                i = j
                continue
            }
            i += 1
        }

        // Deduplicate identical lemma+pos+morphology
        var seen = Set<String>()
        return results.filter { a in
            let key = "\(a.lemmaNorm)|\(a.pos)|\(a.morphology)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    // MARK: - Line helpers

    private struct MorphHit {
        let pos: String
        let morphology: String
    }

    private static func looksLikeMorphLine(_ line: String) -> Bool {
        parseMorphLine(line) != nil
    }

    private static func parseMorphLine(_ line: String) -> MorphHit? {
        // e.g. "cu.stodes             N      3 1 NOM P M"
        // or   "am.o                  V      1 1 PRES ACTIVE  IND 1 S"
        let upper = line.uppercased()
        let hasCase = upper.range(of: #"\b(NOM|GEN|DAT|ACC|ABL|VOC)\b"#, options: .regularExpression) != nil
        let hasTense = upper.range(of: #"\b(PRES|IMPF|FUT|PERF|PLUP|FUTP)\b"#, options: .regularExpression) != nil
        let hasPOS = upper.range(of: #"\b(N|V|ADJ|ADV|PREP|CONJ|INTERJ|PRON|NUM)\b"#, options: .regularExpression) != nil
        guard hasPOS, hasCase || hasTense || upper.contains(" INF") || upper.contains(" IMP") else {
            return nil
        }

        let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tokens.count >= 2 else { return nil }

        var posCode = "unknown"
        var morphTokens: [String] = []
        for (idx, t) in tokens.enumerated() {
            let u = t.uppercased()
            if ["N", "V", "ADJ", "ADV", "PREP", "CONJ", "INTERJ", "PRON", "NUM"].contains(u) {
                posCode = u
                morphTokens = Array(tokens[(idx + 1)...])
                break
            }
        }

        let morphology = formatMorphology(pos: posCode, tokens: morphTokens)
        return MorphHit(pos: humanPOS(posCode), morphology: morphology)
    }

    private struct DictHit {
        let lemma: String
        let lemmaNorm: String
        let pos: String
        let citation: String
    }

    private static func parseDictLine(_ line: String) -> DictHit? {
        // e.g. "custos, custodis  N (3rd) M   [XXXAX]"
        // e.g. "amo, amare, amavi, amatus  V (1st)   [XXXAO]"
        guard line.contains(",") || line.range(of: #"\bN\b|\bV\b|\bADJ\b"#, options: .regularExpression) != nil else {
            return nil
        }
        // Skip pure gloss lines (many lowercase words / semicolons, no POS code near start)
        if looksLikeGloss(line), line.range(of: #"\b[NV]\b|\bADJ\b"#, options: .regularExpression) == nil {
            return nil
        }

        var working = line
        if let bracket = working.range(of: "[") {
            working = String(working[..<bracket.lowerBound]).trimmingCharacters(in: .whitespaces)
        }

        let posPatterns: [(String, String)] = [
            (" ADJ", "adj."), (" V ", "verb"), (" N ", "noun"),
            (" ADV", "adv."), (" PREP", "prep."), (" PRON", "pron.")
        ]
        var pos = "unknown"
        var head = working
        for (marker, label) in posPatterns {
            if let r = working.range(of: marker, options: .caseInsensitive) {
                head = String(working[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                pos = label
                break
            }
        }
        // Trailing " N (3rd) M" without space-padded marker
        if pos == "unknown" {
            let parts = working.split(separator: " ")
            if let idx = parts.firstIndex(where: { ["N", "V", "ADJ", "ADV"].contains($0.uppercased()) }) {
                head = parts[..<idx].joined(separator: " ")
                pos = humanPOS(String(parts[idx]))
            }
        }

        head = head.trimmingCharacters(in: CharacterSet(charactersIn: ",").union(.whitespaces))
        guard !head.isEmpty else { return nil }
        let firstLemma = head.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? head
        // Short readable citation (lemma principal parts) — not the raw WORDS dict line with N/V codes.
        let citation = head.isEmpty ? nil : head
        return DictHit(
            lemma: firstLemma,
            lemmaNorm: firstLemma,
            pos: pos,
            citation: citation ?? firstLemma
        )
    }

    private static func looksLikeGloss(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("|") { return true }
        // English gloss: mostly letters/spaces/punctuation, often ends with ;
        let hasPOS = line.range(of: #"\b(N|V|ADJ)\s+\("#, options: .regularExpression) != nil
        if hasPOS { return false }
        let letterish = line.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letterish > 6 && !line.contains(".")
            || (line.contains(";") && letterish > 4)
    }

    private static func humanPOS(_ code: String) -> String {
        switch code.uppercased() {
        case "N": return "noun"
        case "V": return "verb"
        case "ADJ": return "adj."
        case "ADV": return "adv."
        case "PREP": return "prep."
        case "CONJ": return "conj."
        case "INTERJ": return "interj."
        case "PRON": return "pron."
        case "NUM": return "num."
        default: return code.lowercased()
        }
    }

    private static func formatMorphology(pos: String, tokens: [String]) -> String {
        let u = tokens.map { $0.uppercased() }
        var parts: [String] = []

        let caseMap = ["NOM": "nom.", "GEN": "gen.", "DAT": "dat.", "ACC": "acc.", "ABL": "abl.", "VOC": "voc."]
        let numMap = ["S": "sg.", "P": "pl.", "X": ""]
        let tenseMap = [
            "PRES": "pres.", "IMPF": "impf.", "FUT": "fut.",
            "PERF": "perf.", "PLUP": "plup.", "FUTP": "fut. perf."
        ]
        let voiceMap = ["ACTIVE": "act.", "PASSIVE": "pass."]
        let moodMap = ["IND": "ind.", "SUB": "subj.", "IMP": "imp.", "INF": "inf.", "PPL": "ppl."]
        let personMap = ["1": "1st", "2": "2nd", "3": "3rd"]

        if pos == "N" || pos == "ADJ" || pos == "PRON" {
            for t in u {
                if let c = caseMap[t] { parts.append(c) }
            }
            for t in u {
                if let n = numMap[t], !n.isEmpty { parts.append(n) }
            }
            for t in u where ["M", "F", "N", "C"].contains(t) {
                if t == "C" {
                    parts.append("comm.")
                } else {
                    parts.append(t.lowercased() + ".")
                }
            }
        } else if pos == "V" {
            for t in u {
                if let p = personMap[t] { parts.append(p) }
            }
            for t in u {
                if let n = numMap[t], !n.isEmpty { parts.append(n) }
            }
            for t in u {
                if let x = tenseMap[t] { parts.append(x) }
            }
            for t in u {
                if let x = moodMap[t] { parts.append(x) }
            }
            for t in u {
                if let x = voiceMap[t] { parts.append(x) }
            }
            if u.contains("INF") && !parts.contains("inf.") {
                parts.append("inf.")
            }
        }

        if parts.isEmpty {
            return tokens.joined(separator: " ")
        }
        return parts.joined(separator: " ")
    }
}
