import Foundation

/// Latin headword quantity display (user decision): macrons only, breves dropped,
/// except anceps vowels, which L&S writes as macron+`^` (ā^) or breve+`_` (ă_): these keep
/// both marks L&S-style (ā̆ / ă̄), e.g. acadēmī̆a (user decision 2026-10-13).
/// Display-time only: lat.sqlite stays pristine and search keys (`lemma_norm`)
/// already ignore all quantity marks.
enum LatinQuantity {
    private static let macron: Unicode.Scalar = "\u{0304}"
    private static let breve: Unicode.Scalar = "\u{0306}"
    private static let vowels = Set("aeiouyAEIOUY".unicodeScalars)
    /// Greek words quoted in L&S also carry `^`/`_` (βα^ρύς): render as LSJ-style ᾰ / ᾱ.
    private static let greekVowels = Set("αιυΑΙΥ".unicodeScalars)

    /// Display-time corrections of L&S source oddities to TLL quantities (user decision
    /// 2026-10-13: TLL authoritative). Documented in build/tll_corrections.md.
    static let tllCorrections: [(String, String)] = [
        ("consú^ētē", "cōnsuētē"),
        ("dēstrictárĭum", "dēstrictārĭum"),
        ("augùrātĭo", "augurātĭo"),
        ("augùrālis", "augurālis"),
        ("circum-tuèŏr", "circum-tueor"),
        ("nătātìcĭus", "nătātĭcĭus"),   // TLL natāticius (vel natātitius)
        ("abscído", "abscīdo"),         // ab-cīdo: TLL abscīdo
        ("ìtúm", "ĭtum"),               // cŭbo, ŭi, ĭtum (cubitum)
        ("ìtum", "ĭtum"),               // per-dŏlĕo; ē-lĭcĭo lĭcĭtum
        ("féra", "fĕra"),               // multĭ-fer, fĕra, fĕrum
        ("ullà", "ullā"),               // abl. f.: variatione ullā; nullā conscientiā
        ("-_ia", "-ia"),                // Ĕrўthēa: stray `_` (not in TLL), form left as is
    ].map { ($0.0.precomposedStringWithCanonicalMapping, $0.1.precomposedStringWithCanonicalMapping) }

    static func corrected(_ s: String) -> String {
        var t = s.precomposedStringWithCanonicalMapping
        for (from, to) in tllCorrections where t.contains(from) { t = t.replacingOccurrences(of: from, with: to) }
        return t
    }

    /// Headwords, lemma lines, inflection notes, Morpheus/WORDS forms.
    static func display(_ raw: String) -> String {
        let s = corrected(raw)
        guard s.decomposedStringWithCanonicalMapping.unicodeScalars.contains(where: { $0 == breve || $0 == "^" || $0 == "_" || $0 == "\u{045E}" || $0 == "\u{040E}" }) else {
            return s
        }
        // L&S uses Cyrillic ў (U+045E) for y-breve (Abdalonўmus): show plain Latin y.
        let src = Array(s.decomposedStringWithCanonicalMapping.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        var lastBase: Unicode.Scalar? = nil
        while i < src.count {
            let c = src[i]
            let next: Unicode.Scalar? = i + 1 < src.count ? src[i + 1] : nil
            if c == "\u{0443}" && next == breve { out.append("y"); lastBase = "y"; i += 2; continue }
            if c == "\u{0423}" && next == breve { out.append("Y"); lastBase = "Y"; i += 2; continue }
            if c == macron, next == "^", let b = lastBase, vowels.contains(b) {
                out.append(macron); out.append(breve); i += 2; continue          // ā^ → ā̆
            }
            if c == breve, let b = lastBase, vowels.contains(b) {
                if next == "_" { out.append(breve); out.append(macron); i += 2; continue }  // ă_ → ă̄
                i += 1; continue  // plain breve: drop
            }
            // Bare L&S quantity marks after any other vowel (+marks), e.g. discŏï_des:
            // `_` = long → macron; `^` = short → dropped like a plain breve.
            if c == "^" || c == "_", let b = lastBase, greekVowels.contains(b) {
                out.append(c == "_" ? macron : breve); i += 1; continue
            }
            if c == "_", let b = lastBase, vowels.contains(b) { out.append(macron); i += 1; continue }
            if c == "^", let b = lastBase, vowels.contains(b) { i += 1; continue }
            out.append(c)
            if !(0x0300...0x036F).contains(c.value) { lastBase = c }
            i += 1
        }
        return String(out).precomposedStringWithCanonicalMapping
    }

    /// Article body: breves stay (metrical evidence), but L&S's ASCII quantity markers and
    /// Cyrillic ў are rendered as the marks they stand for: ā^ → ā̆, ă_ → ă̄, V_ → V̄, V^ → V̆,
    /// ў → y̆. No mark is ever removed.
    static func bodyDisplay(_ raw: String) -> String {
        let s = corrected(raw)
        guard s.contains(where: { $0 == "^" || $0 == "_" || $0 == "\u{045E}" || $0 == "\u{040E}" }) else { return s }
        let src = Array(s.decomposedStringWithCanonicalMapping.unicodeScalars)
        var out = String.UnicodeScalarView()
        var lastBase: Unicode.Scalar? = nil
        for (i, c) in src.enumerated() {
            let next: Unicode.Scalar? = i + 1 < src.count ? src[i + 1] : nil
            // ў = у + breve: Latin y, keep the breve that follows.
            if c == "\u{0443}" && next == breve { out.append("y"); lastBase = "y"; continue }
            if c == "\u{0423}" && next == breve { out.append("Y"); lastBase = "Y"; continue }
            if (c == "_" || c == "^"), let b = lastBase, vowels.contains(b) || greekVowels.contains(b) {
                out.append(c == "_" ? macron : breve); continue
            }
            out.append(c)
            if !(0x0300...0x036F).contains(c.value) { lastBase = c }
        }
        return String(out).precomposedStringWithCanonicalMapping
    }

    /// Article HTML: apply `display` to the lemma line and inflection notes only — the text
    /// from the start up to the first parenthesis, citation, quotation, etymology or sense.
    /// Body breves stay: L&S uses them as metrical evidence ("cf. ăbĭci, Ov. P. 2, 3, 37").
    static func displayHTML(_ html: String) -> String {
        let stops = ["(", "<span class=\"sense", "<cite", "<q", "<span class=\"cit", "<span class=\"etym", "<div"]
        var cut = html.endIndex
        let searchFrom = html.range(of: "</h1>")?.upperBound ?? html.startIndex
        for s in stops {
            if let r = html.range(of: s, range: searchFrom..<html.endIndex), r.lowerBound < cut { cut = r.lowerBound }
        }
        let head = String(html[..<cut])
        // Transform text nodes only, never tags/attributes.
        var result = ""
        var text = ""
        var inTag = false
        for ch in head {
            if ch == "<" { result += display(text); text = ""; inTag = true; result.append(ch); continue }
            if inTag { result.append(ch); if ch == ">" { inTag = false }; continue }
            text.append(ch)
        }
        result += display(text)
        // Body: text nodes only.
        var body = ""
        text = ""
        inTag = false
        for ch in html[cut...] {
            if ch == "<" { body += bodyDisplay(text); text = ""; inTag = true; body.append(ch); continue }
            if inTag { body.append(ch); if ch == ">" { inTag = false }; continue }
            text.append(ch)
        }
        body += bodyDisplay(text)
        return result + body
    }
}
