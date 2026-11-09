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
            if parseMorphLine(lines[i]) != nil {
                // Neuter lemmas (memorial) print several morph lines, then one dict+gloss
                // block. Attach that shared block to every preceding morph line.
                var morphHits: [MorphHit] = []
                var j = i
                while j < lines.count, let hit = parseMorphLine(lines[j]) {
                    morphHits.append(hit)
                    j += 1
                }

                var lemma = MorphPreprocess.latinLookupKey(surfaceForm)
                var lemmaDisplay = surfaceForm
                var dictPOS: String?
                var citation: String?
                var glossParts: [String] = []

                while j < lines.count {
                    let next = lines[j]
                    if looksLikeMorphLine(next) { break }
                    if let dict = parseDictLine(next) {
                        lemmaDisplay = dict.lemma
                        lemma = MorphPreprocess.latinLookupKey(dict.lemmaNorm)
                        if !dict.pos.isEmpty { dictPOS = dict.pos }
                        citation = dict.citation
                    } else if looksLikeGloss(next) {
                        glossParts.append(next.trimmingCharacters(in: CharacterSet(charactersIn: "|")))
                    } else if next.hasPrefix("=>") || next.hasPrefix("*") {
                        break
                    }
                    j += 1
                }

                let gloss = glossParts.isEmpty ? nil : glossParts.joined(separator: " ")
                let lemmaDisplayClean = Self.cleanedLemma(lemmaDisplay)
                let lemmaClean = MorphPreprocess.latinLookupKey(Self.cleanedLemma(lemma))
                let pos = (dictPOS?.isEmpty == false) ? dictPOS! : (morphHits.first?.pos ?? "unknown")
                let morphology = MorphologyMerge.combine(morphHits.map(\.morphology))
                results.append(
                    Analysis(
                        lemma: lemmaDisplayClean,
                        lemmaNorm: lemmaClean,
                        language: .latin,
                        pos: pos,
                        morphology: morphology,
                        quantity: citation,
                        gloss: gloss
                    )
                )
                i = j
                continue
            }
            i += 1
        }

        // Dictionary-only output (no morph line): still a real WORDS entry.
        if results.isEmpty {
            var j = 0
            while j < lines.count {
                let line = lines[j]
                if !looksLikeMorphLine(line), let dict = parseDictLine(line) {
                    var glossParts: [String] = []
                    var k = j + 1
                    while k < lines.count {
                        let next = lines[k]
                        if looksLikeMorphLine(next) || parseDictLine(next) != nil { break }
                        if looksLikeGloss(next) {
                            glossParts.append(next.trimmingCharacters(in: CharacterSet(charactersIn: "|")))
                        } else if next.hasPrefix("=>") || next.hasPrefix("*") {
                            break
                        }
                        k += 1
                    }
                    let gloss = glossParts.isEmpty ? nil : glossParts.joined(separator: " ")
                    results.append(
                        Analysis(
                            lemma: Self.cleanedLemma(dict.lemma),
                            lemmaNorm: MorphPreprocess.latinLookupKey(Self.cleanedLemma(dict.lemmaNorm)),
                            language: .latin,
                            pos: dict.pos.isEmpty ? "unknown" : dict.pos,
                            morphology: "",
                            quantity: dict.citation,
                            gloss: gloss
                        )
                    )
                    j = k
                    continue
                }
                j += 1
            }
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
        case "ADJ": return "adjective"
        case "ADV": return "adv."
        case "PREP": return "prep."
        case "CONJ": return "conj."
        case "INTERJ": return "interj."
        case "PRON": return "pron."
        case "NUM": return "num."
        default: return code.lowercased()
        }
    }

    /// WORDS writes stem.ending (`natural.e`); the lexicon lemma has no dot.
    private static func cleanedLemma(_ raw: String) -> String {
        raw.replacingOccurrences(of: ".", with: "")
    }

    private static func formatMorphology(pos: String, tokens: [String]) -> String {
        let u = tokens.map { $0.uppercased() }

        let caseMap = ["NOM": "nom", "GEN": "gen", "DAT": "dat", "ACC": "acc", "ABL": "abl", "VOC": "voc"]
        let tenseMap = [
            "PRES": "pres", "IMPF": "impf", "FUT": "fut",
            "PERF": "perf", "PLUP": "plup", "FUTP": "futp"
        ]
        let voiceMap = ["ACTIVE": "act", "PASSIVE": "pass"]
        let moodMap = ["IND": "ind", "SUB": "subj", "IMP": "imp", "INF": "inf", "PPL": "ppl"]
        let personMap = ["1": "1st", "2": "2nd", "3": "3rd"]

        if pos == "N" || pos == "ADJ" || pos == "PRON" {
            var gender: String?
            var cases: [String] = []
            var number: String?
            var degree: String?
            for t in u {
                if let c = caseMap[t] {
                    cases.append(c)
                } else if t == "S" {
                    number = "sg"
                } else if t == "P" {
                    number = "pl"
                } else if t == "M" {
                    gender = "masc"
                } else if t == "F" {
                    gender = "fem"
                } else if t == "N" {
                    gender = "neut"
                } else if t == "C" {
                    gender = "comm."
                } else if t == "COMP" {
                    degree = "comp."
                } else if t == "SUPER" {
                    degree = "superl."
                }
            }
            var parts: [String] = []
            if let gender { parts.append(gender) }
            if !cases.isEmpty { parts.append(cases.joined(separator: "/")) }
            if let number { parts.append(number) }
            if let degree { parts.append(degree) }
            return parts.isEmpty ? tokens.joined(separator: " ") : parts.joined(separator: " ")
        }

        if pos == "V" {
            var tense: String?
            var mood: String?
            var voice: String?
            var person: String?
            var number: String?
            // Person is the last 1/2/3 (conjugation numbers come first).
            for t in u {
                if let x = tenseMap[t] { tense = x }
                else if let x = moodMap[t] { mood = x }
                else if let x = voiceMap[t] { voice = x }
                else if t == "S" { number = "sg" }
                else if t == "P" { number = "pl" }
                else if let p = personMap[t] { person = p }
            }
            if u.contains("INF") { mood = "inf" }
            var parts: [String] = []
            if let tense { parts.append(tense) }
            if let mood { parts.append(mood) }
            if let voice { parts.append(voice) }
            if let person { parts.append(person) }
            if let number { parts.append(number) }
            return parts.isEmpty ? tokens.joined(separator: " ") : parts.joined(separator: " ")
        }

        return tokens.joined(separator: " ")
    }
}
