import Foundation

enum GenderRefiner: Sendable {

    enum DictGender: Equatable {
        case masc, fem, neut, common
    }

    /// Map L&S-style labels (`m.`, `f.`, `n.`, `comm.`) — never TLL `c` as output.
    static func gender(fromDictionaryPOS pos: String) -> DictGender? {
        let s = pos.lowercased()
            .replacingOccurrences(of: " ", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: ".;,"))
        if s.hasPrefix("comm") || s == "common" || s == "c" || s == "mf" || s == "m/f" {
            return .common
        }
        if s == "m" || s.hasPrefix("m.") || s.hasPrefix("masc") { return .masc }
        if s == "f" || s.hasPrefix("f.") || s.hasPrefix("fem") { return .fem }
        if s == "n" || s.hasPrefix("n.") || s.hasPrefix("neut") { return .neut }
        return nil
    }

    /// Display token for analysis list (L&S convention).
    static func displayToken(_ g: DictGender) -> String {
        switch g {
        case .masc: return "masc"
        case .fem: return "fem"
        case .neut: return "neut"
        case .common: return "comm."
        }
    }

    /// Extract gender from `class="pos"` or Perseus `class="gen"`.
    static func dictionaryPOS(fromHTML html: String) -> String? {
        let patterns = [
            #"<p[^>]*class="pos"[^>]*>(.*?)</p>"#,
            #"<span[^>]*class="gen"[^>]*>(.*?)</span>"#,
            #"<[^>]*class="gen"[^>]*>(.*?)</[^>]+>"#,
        ]
        for pat in patterns {
            if let r = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive, .dotMatchesLineSeparators]),
               let m = r.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
               let range = Range(m.range(at: 1), in: html) {
                let inner = String(html[range])
                    .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !inner.isEmpty { return inner }
            }
        }
        return nil
    }

    static func refineMorphology(_ morphology: String, dictionaryPOS: String?) -> String {
        guard let dictionaryPOS,
              let g = gender(fromDictionaryPOS: dictionaryPOS) else {
            return morphology
        }
        let token = displayToken(g)
        let ambiguous = ["masc/fem", "masc/neut", "fem/neut", "masc/fem/neut"]
        var out = morphology
        for a in ambiguous where out.contains(a) {
            out = out.replacingOccurrences(of: a, with: token)
        }
        return out
    }

    // MARK: - Greek (LSJ article as gender: ὁ / ἡ / τό)

    private static let greekArticles: Set<String> = ["ὁ", "ἡ", "τό"]

    /// LSJ gender as printed by LSJ: first `class="gen"` in the entry head
    /// (before the first translation), e.g. "ὁ", "ἡ", "τό". When LSJ prints the article
    /// only in running head text (παῖς: "παιδός, ὁ, ἡ"), read a comma-separated run
    /// of articles from the head. Nil when LSJ gives none (caller keeps Morpheus).
    static func lsjGender(fromHTML html: String) -> String? {
        var head = html
        // Head = everything before the first translation (`class="tr"`); LSJ prints
        // the article before the gloss, sometimes after a long dialect note.
        if let r = html.range(of: #"class="tr""#) { head = String(html[..<r.lowerBound]) }
        if let r = try? NSRegularExpression(pattern: #"<span[^>]*class="gen"[^>]*>(.*?)</span>"#, options: [.dotMatchesLineSeparators]),
           let m = r.firstMatch(in: head, range: NSRange(head.startIndex..., in: head)),
           let range = Range(m.range(at: 1), in: head) {
            let inner = String(head[range])
                .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let norm = normalizeArticleRun(inner) { return norm }
        }
        // Fallback: article run in head text ("…, ὁ, ἡ, …").
        let text = head.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let tokens = text.components(separatedBy: CharacterSet(charactersIn: ",;:()").union(.whitespacesAndNewlines))
            .filter { !$0.isEmpty }
        var run: [String] = []
        for t in tokens {
            if greekArticles.contains(t) {
                if !run.contains(t) { run.append(t) }
            } else if !run.isEmpty {
                break
            }
        }
        return run.isEmpty ? nil : run.joined(separator: ", ")
    }

    private static func normalizeArticleRun(_ s: String) -> String? {
        let parts = s.components(separatedBy: CharacterSet(charactersIn: ",").union(.whitespacesAndNewlines))
            .filter { !$0.isEmpty }
        guard !parts.isEmpty, parts.allSatisfy({ greekArticles.contains($0) }) else { return nil }
        return parts.joined(separator: ", ")
    }

    private static let morpheusGenderRun = try! NSRegularExpression(
        pattern: #"\b(?:masc|fem|neut)(?:/(?:masc|fem|neut))*\b"#)

    /// Replace Morpheus gender (masc, fem, masc/fem, …) with the LSJ article.
    static func refineGreekMorphology(_ morphology: String, lsjGender: String) -> String {
        morpheusGenderRun.stringByReplacingMatches(
            in: morphology, range: NSRange(morphology.startIndex..., in: morphology),
            withTemplate: NSRegularExpression.escapedTemplate(for: lsjGender))
    }

    /// Use lexicon HTML only (SQLite L&S / seed). Do not prefer a conflicting curated shortcut.
    static func refine(_ analysis: Analysis, articleHTML: String?, seedHTML: String? = nil) -> Analysis {
        _ = seedHTML // unused; kept so call sites stay stable
        if analysis.language == .greek {
            guard let html = articleHTML, let g = lsjGender(fromHTML: html) else { return analysis }
            let newMorph = refineGreekMorphology(analysis.morphology, lsjGender: g)
            if newMorph == analysis.morphology { return analysis }
            return Analysis(id: analysis.id, lemma: analysis.lemma, lemmaNorm: analysis.lemmaNorm,
                            language: analysis.language, pos: analysis.pos, morphology: newMorph,
                            quantity: analysis.quantity, gloss: analysis.gloss, homograph: analysis.homograph)
        }
        guard let html = articleHTML,
              let pos = dictionaryPOS(fromHTML: html) else {
            return analysis
        }
        let newMorph = refineMorphology(analysis.morphology, dictionaryPOS: pos)
        if newMorph == analysis.morphology { return analysis }
        return Analysis(
            id: analysis.id,
            lemma: analysis.lemma,
            lemmaNorm: analysis.lemmaNorm,
            language: analysis.language,
            pos: analysis.pos,
            morphology: newMorph,
            quantity: analysis.quantity,
            gloss: analysis.gloss,
            homograph: analysis.homograph
        )
    }
}
