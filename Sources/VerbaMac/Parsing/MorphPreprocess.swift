import Foundation

/// Preprocessing helpers for Morpheus lookup keys (SPEC).
enum MorphPreprocess: Sendable {

    /// Strip trailing Latin enclitics `-que` / `-ne` / `-ve` (longest match first).
    /// Returns `(stem, enclitic?)`. Does not strip when the remainder would be empty.
    static func stripLatinEnclitic(_ raw: String) -> (stem: String, enclitic: String?) {
        let lower = raw.lowercased()
        for enclitic in ["que", "ne", "ve"] {
            if lower.hasSuffix(enclitic), lower.count > enclitic.count {
                let end = raw.index(raw.endIndex, offsetBy: -enclitic.count)
                let stem = String(raw[..<end])
                if !stem.isEmpty {
                    return (stem, enclitic)
                }
            }
        }
        return (raw, nil)
    }

    /// Latin lookup key: lowercase, fold `v→u` / `j→i`, strip combining diacritics / macrons.
    static func latinLookupKey(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        s = s
            .replacingOccurrences(of: "v", with: "u")
            .replacingOccurrences(of: "j", with: "i")
            .replacingOccurrences(of: "ў", with: "y")       // L&S Cyrillic y-breve
            .replacingOccurrences(of: "\u{0443}", with: "y")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "‐", with: "") // unicode hyphen
            .replacingOccurrences(of: "‑", with: "")
        s = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return s
    }

    /// Greek: Unicode NFC, then optionally strip accents for `-n` path / lexicon join.
    static func greekNFC(_ raw: String) -> String {
        // Pasted text can carry invisible format chars (LRM/RLM, ZWSP, BOM, soft hyphen).
        // NFC also folds oxia (U+1F71 ά) into tonos (U+03AC ά).
        String(String.UnicodeScalarView(raw.unicodeScalars.filter {
            $0.properties.generalCategory != .format
        }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    /// Accent-stripped Greek base letters (for lemma_norm join).
    static func greekBase(_ raw: String) -> String {
        let folded = greekNFC(raw)
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "el_GR"))
        return String(folded.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) })
    }

    /// True if the string contains Greek letters (BMP Greek or extended).
    static func looksGreek(_ raw: String) -> Bool {
        raw.unicodeScalars.contains {
            (0x0370...0x03FF).contains($0.value) || (0x1F00...0x1FFF).contains($0.value)
        }
    }
}
