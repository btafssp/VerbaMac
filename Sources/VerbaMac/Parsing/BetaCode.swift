import Foundation

/// Minimal Perseus-style Greek Beta Code ↔ Unicode converter for Morpheus I/O.
///
/// Classic `cruncher` expects Greek in Beta Code (`a)/nqrwpos`), not Unicode.
/// Coverage is the common polytonic set used by Perseus Morpheus; not a full TLG map.
enum BetaCode: Sendable {

    /// Convert Unicode Greek to Beta Code. Non-Greek characters pass through.
    static func fromGreek(_ unicode: String) -> String {
        let nfc = unicode.precomposedStringWithCanonicalMapping
        var out = ""
        out.reserveCapacity(nfc.count * 2)
        for ch in nfc {
            if let mapped = unicodeToBeta[ch] {
                out.append(perseusCapitalOrder(mapped))
            } else if let scalar = ch.unicodeScalars.first,
                      ch.unicodeScalars.count == 1,
                      let decomposed = decomposePolytonic(scalar) {
                out.append(perseusCapitalOrder(decomposed))
            } else {
                out.append(ch)
            }
        }
        return out
    }

    /// Perseus/Morpheus Beta Code puts a capital's diacritics between `*` and the
    /// letter (`*)a` = Ἀ, `*(/a` = Ἅ). Reorder `*a)` → `*)a`; lowercase passes through.
    static func perseusCapitalOrder(_ b: String) -> String {
        guard b.hasPrefix("*"), b.count > 2 else { return b }
        let rest = b.dropFirst()
        let letter = rest.first!
        guard letter.isLetter else { return b }
        return "*" + String(rest.dropFirst()) + String(letter)
    }

    /// Convert Beta Code lemma/form to Unicode Greek for display.
    /// Also maps Latin quantity `_` after a vowel to a combining macron letter (a_ → ā).
    static func toDisplay(_ beta: String) -> String {
        var result = ""
        result.reserveCapacity(beta.count)
        var i = beta.startIndex

        while i < beta.endIndex {
            if beta[i] == "*" {
                i = beta.index(after: i)
                // Perseus order: diacritics may precede the capital letter (`*)anti/oxos`).
                let (pre, afterPre) = readDiacritics(beta, from: i)
                i = afterPre
                guard i < beta.endIndex else { break }
                let base = String(beta[i]).lowercased()
                i = beta.index(after: i)
                let (post, next) = readDiacritics(beta, from: i)
                let diacritics = pre + post
                i = next
                if let letter = betaLetterToUnicode(base, capital: true, diacritics: diacritics) {
                    result.append(letter)
                } else {
                    result.append("*")
                    result.append(contentsOf: base)
                    result.append(contentsOf: diacritics.map(\.rawValue).joined())
                }
                continue
            }

            let ch = String(beta[i])
            if isBetaBaseLetter(ch) {
                i = beta.index(after: i)
                let (diacritics, next) = readDiacritics(beta, from: i)
                i = next
                if let letter = betaLetterToUnicode(ch, capital: false, diacritics: diacritics) {
                    result.append(letter)
                } else {
                    result.append(contentsOf: ch)
                    result.append(contentsOf: diacritics.map(\.rawValue).joined())
                }
                continue
            }

            if beta[i] == "_", !result.isEmpty {
                let last = result.removeLast()
                if let macron = latinMacron[last] {
                    result.append(macron)
                } else {
                    result.append(last)
                    result.append("_")
                }
                i = beta.index(after: i)
                continue
            }

            result.append(beta[i])
            i = beta.index(after: i)
        }
        return finalizeSigma(result)
    }

    /// Word-final σ → ς (λόγοσ → λόγος, παῖσ → παῖς). A σ is final when a letter
    /// precedes it and no letter (Greek or other) follows. Combining marks count as
    /// part of the preceding letter.
    static func finalizeSigma(_ s: String) -> String {
        guard s.contains("σ") else { return s }
        let chars = Array(s)
        var out = ""
        out.reserveCapacity(s.count)
        for (k, c) in chars.enumerated() {
            if c == "σ", k > 0, chars[k - 1].isLetter,
               k + 1 == chars.count || !chars[k + 1].isLetter {
                out.append("ς")
            } else {
                out.append(c)
            }
        }
        return out
    }


    /// Latin Morpheus forms: keep Latin letters; only map quantity `_` (a_ → ā).
    /// Do **not** run Greek Beta Code conversion on Latin lemmas (amo ≠ εμο).
    static func latinToDisplay(_ form: String) -> String {
        var result = ""
        result.reserveCapacity(form.count)
        var i = form.startIndex
        while i < form.endIndex {
            if form[i] == "_", !result.isEmpty {
                let last = result.removeLast()
                if let macron = latinMacron[last] {
                    result.append(macron)
                } else {
                    result.append(last)
                    result.append("_")
                }
                i = form.index(after: i)
                continue
            }
            result.append(form[i])
            i = form.index(after: i)
        }
        return result
    }

    /// Strip Beta Code diacritics for lemma_norm-style keys.
    static func stripDiacritics(_ beta: String) -> String {
        let markers = CharacterSet(charactersIn: "()/=\\+|^*")
        return String(beta.unicodeScalars.filter { !markers.contains($0) })
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
    }

    // MARK: - Internals

    private enum Diacritic: String {
        case smooth = ")"
        case rough = "("
        case acute = "/"
        case grave = "\\"
        case circumflex = "="
        case iota = "|"
        case diaeresis = "+"
    }

    private static func readDiacritics(_ s: String, from i: String.Index) -> ([Diacritic], String.Index) {
        var idx = i
        var found: [Diacritic] = []
        while idx < s.endIndex {
            let c = String(s[idx])
            guard let d = Diacritic(rawValue: c) else { break }
            found.append(d)
            idx = s.index(after: idx)
        }
        return (found, idx)
    }

    private static func isBetaBaseLetter(_ s: String) -> Bool {
        guard s.count == 1, let c = s.first else { return false }
        return "abgdezhqiklmncoprstufxyw".contains(c)
    }

    private static let latinMacron: [Character: Character] = [
        "a": "ā", "e": "ē", "i": "ī", "o": "ō", "u": "ū", "y": "ȳ",
        "A": "Ā", "E": "Ē", "I": "Ī", "O": "Ō", "U": "Ū", "Y": "Ȳ"
    ]

    private static let unicodeToBeta: [Character: String] = {
        var m: [Character: String] = [:]
        let clean: [(Character, String)] = [
            ("α", "a"), ("β", "b"), ("γ", "g"), ("δ", "d"), ("ε", "e"),
            ("ζ", "z"), ("η", "h"), ("θ", "q"), ("ι", "i"), ("κ", "k"),
            ("λ", "l"), ("μ", "m"), ("ν", "n"), ("ξ", "c"), ("ο", "o"),
            ("π", "p"), ("ρ", "r"), ("σ", "s"), ("ς", "s"), ("τ", "t"),
            ("υ", "u"), ("φ", "f"), ("χ", "x"), ("ψ", "y"), ("ω", "w"),
            ("Α", "*a"), ("Β", "*b"), ("Γ", "*g"), ("Δ", "*d"), ("Ε", "*e"),
            ("Ζ", "*z"), ("Η", "*h"), ("Θ", "*q"), ("Ι", "*i"), ("Κ", "*k"),
            ("Λ", "*l"), ("Μ", "*m"), ("Ν", "*n"), ("Ξ", "*c"), ("Ο", "*o"),
            ("Π", "*p"), ("Ρ", "*r"), ("Σ", "*s"), ("Τ", "*t"), ("Υ", "*u"),
            ("Φ", "*f"), ("Χ", "*x"), ("Ψ", "*y"), ("Ω", "*w"),
            ("ά", "a/"), ("έ", "e/"), ("ή", "h/"), ("ί", "i/"), ("ό", "o/"),
            ("ύ", "u/"), ("ώ", "w/"),
            ("ὰ", "a\\"), ("ὲ", "e\\"), ("ὴ", "h\\"), ("ὶ", "i\\"), ("ὸ", "o\\"),
            ("ὺ", "u\\"), ("ὼ", "w\\"),
            ("ᾶ", "a="), ("ῆ", "h="), ("ῖ", "i="), ("ῦ", "u="), ("ῶ", "w="),
            ("ἀ", "a)"), ("ἁ", "a("), ("ἐ", "e)"), ("ἑ", "e("),
            ("ἠ", "h)"), ("ἡ", "h("), ("ἰ", "i)"), ("ἱ", "i("),
            ("ὀ", "o)"), ("ὁ", "o("), ("ὐ", "u)"), ("ὑ", "u("),
            ("ὠ", "w)"), ("ὡ", "w("), ("ῤ", "r)"), ("ῥ", "r("),
            ("ἄ", "a)/"), ("ἅ", "a(/"), ("ἔ", "e)/"), ("ἕ", "e(/"),
            ("ἤ", "h)/"), ("ἥ", "h(/"), ("ἴ", "i)/"), ("ἵ", "i(/"),
            ("ὄ", "o)/"), ("ὅ", "o(/"), ("ὔ", "u)/"), ("ὕ", "u(/"),
            ("ὤ", "w)/"), ("ὥ", "w(/"),
            ("ἂ", "a)\\"), ("ἃ", "a(\\"), ("ἒ", "e)\\"), ("ἓ", "e(\\"),
            ("ἢ", "h)\\"), ("ἣ", "h(\\"), ("ἲ", "i)\\"), ("ἳ", "i(\\"),
            ("ὂ", "o)\\"), ("ὃ", "o(\\"), ("ὒ", "u)\\"), ("ὓ", "u(\\"),
            ("ὢ", "w)\\"), ("ὣ", "w(\\"),
            ("ἆ", "a)="), ("ἇ", "a(="), ("ἦ", "h)="), ("ἧ", "h(="),
            ("ἶ", "i)="), ("ἷ", "i(="), ("ὖ", "u)="), ("ὗ", "u(="),
            ("ὦ", "w)="), ("ὧ", "w(="),
            ("ᾳ", "a|"), ("ῃ", "h|"), ("ῳ", "w|"),
            ("ᾴ", "a/|"), ("ῄ", "h/|"), ("ῴ", "w/|"),
            ("ᾷ", "a=|"), ("ῇ", "h=|"), ("ῷ", "w=|"),
            ("ᾀ", "a)|"), ("ᾁ", "a(|"), ("ᾐ", "h)|"), ("ᾑ", "h(|"),
            ("ᾠ", "w)|"), ("ᾡ", "w(|"),
            ("ᾄ", "a)/|"), ("ᾅ", "a(/|"), ("ᾔ", "h)/|"), ("ᾕ", "h(/|"),
            ("ᾤ", "w)/|"), ("ᾥ", "w(/|"),
            ("ᾆ", "a)=|"), ("ᾇ", "a(=|"), ("ᾖ", "h)=|"), ("ᾗ", "h(=|"),
            ("ᾦ", "w)=|"), ("ᾧ", "w(=|"),
            ("ϊ", "i+"), ("ϋ", "u+"), ("ΐ", "i+/"), ("ΰ", "u+/"),
            ("Ἄ", "*a)/"), ("Ἁ", "*a("), ("Ἀ", "*a)"), ("Ἅ", "*a(/"),
            ("Ἐ", "*e)"), ("Ἑ", "*e("), ("Ἔ", "*e)/"), ("Ἕ", "*e(/"),
            ("Ἠ", "*h)"), ("Ἡ", "*h("), ("Ἤ", "*h)/"), ("Ἥ", "*h(/"),
            ("Ἰ", "*i)"), ("Ἱ", "*i("), ("Ἴ", "*i)/"), ("Ἵ", "*i(/"),
            ("Ὀ", "*o)"), ("Ὁ", "*o("), ("Ὄ", "*o)/"), ("Ὅ", "*o(/"),
            ("Ὑ", "*u("), ("Ὕ", "*u(/"),
            ("Ὠ", "*w)"), ("Ὡ", "*w("), ("Ὤ", "*w)/"), ("Ὥ", "*w(/"),
            ("Ῥ", "*r("),
            ("Ά", "*a/"), ("Έ", "*e/"), ("Ή", "*h/"), ("Ί", "*i/"),
            ("Ό", "*o/"), ("Ύ", "*u/"), ("Ώ", "*w/")
        ]
        for (u, b) in clean { m[u] = b }
        return m
    }()

    private static func decomposePolytonic(_ scalar: Unicode.Scalar) -> String? {
        let s = String(scalar).decomposedStringWithCanonicalMapping
        var baseBeta: String?
        var marks = ""
        for sc in s.unicodeScalars {
            if let b = unicodeToBeta[Character(sc)] {
                if baseBeta == nil { baseBeta = b } else { marks += b }
            } else {
                switch sc.value {
                case 0x0313: marks += ")"
                case 0x0314: marks += "("
                case 0x0301: marks += "/"
                case 0x0300: marks += "\\"
                case 0x0342: marks += "="
                case 0x0345: marks += "|"
                case 0x0308: marks += "+"
                default: break
                }
            }
        }
        guard let base = baseBeta else { return nil }
        return base + marks
    }

    private static func betaLetterToUnicode(
        _ base: String,
        capital: Bool,
        diacritics: [Diacritic]
    ) -> Character? {
        let lowerMap: [String: Character] = [
            "a": "α", "b": "β", "g": "γ", "d": "δ", "e": "ε",
            "z": "ζ", "h": "η", "q": "θ", "i": "ι", "k": "κ",
            "l": "λ", "m": "μ", "n": "ν", "c": "ξ", "o": "ο",
            "p": "π", "r": "ρ", "s": "σ", "t": "τ", "u": "υ",
            "f": "φ", "x": "χ", "y": "ψ", "w": "ω"
        ]
        let upperMap: [String: Character] = [
            "a": "Α", "b": "Β", "g": "Γ", "d": "Δ", "e": "Ε",
            "z": "Ζ", "h": "Η", "q": "Θ", "i": "Ι", "k": "Κ",
            "l": "Λ", "m": "Μ", "n": "Ν", "c": "Ξ", "o": "Ο",
            "p": "Π", "r": "Ρ", "s": "Σ", "t": "Τ", "u": "Υ",
            "f": "Φ", "x": "Χ", "y": "Ψ", "w": "Ω"
        ]
        guard let plain = (capital ? upperMap : lowerMap)[base] else { return nil }
        if diacritics.isEmpty { return plain }

        var scalars = String(plain).unicodeScalars
        for d in diacritics {
            let mark: Unicode.Scalar?
            switch d {
            case .smooth: mark = Unicode.Scalar(0x0313)
            case .rough: mark = Unicode.Scalar(0x0314)
            case .acute: mark = Unicode.Scalar(0x0301)
            case .grave: mark = Unicode.Scalar(0x0300)
            case .circumflex: mark = Unicode.Scalar(0x0342)
            case .iota: mark = Unicode.Scalar(0x0345)
            case .diaeresis: mark = Unicode.Scalar(0x0308)
            }
            if let mark { scalars.append(mark) }
        }
        let composed = String(String.UnicodeScalarView(scalars)).precomposedStringWithCanonicalMapping
        return composed.first
    }
}
