import Foundation

/// LSJ cross-reference link written by the importer:
/// `verba-xref:grc?l=<lemma>&h=<homograph>&s=<section>` (section like "B" or "B.II").
struct CrossReferenceLink: Equatable, Sendable {
    let lemma: String
    let homograph: Int?
    let section: String?

    init(lemma: String, homograph: Int? = nil, section: String? = nil) {
        self.lemma = lemma
        self.homograph = homograph
        self.section = section
    }

    init?(url: URL) {
        guard url.scheme == "verba-xref",
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems,
              let lemma = items.first(where: { $0.name == "l" })?.value, !lemma.isEmpty else { return nil }
        self.lemma = lemma
        self.homograph = items.first(where: { $0.name == "h" })?.value.flatMap { Int($0) }
        let s = items.first(where: { $0.name == "s" })?.value
        self.section = (s?.isEmpty == false) ? s : nil
    }

    /// JS that scrolls the article to a section anchor (`id="sec-B.II"`), falling back to the
    /// first sense whose `data-path` ends with the label ("II" → "A.II"). Nil section → top.
    static func scrollScript(section: String?) -> String {
        guard let section else { return "window.scrollTo(0,0);" }
        let json = (try? JSONSerialization.data(withJSONObject: [section], options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\"]"
        return """
        (function(){ var s = \(json)[0];
          var e = document.getElementById('sec-' + s);
          if (!e) { var all = document.querySelectorAll('[data-path]');
            for (var i = 0; i < all.length; i++) { var p = all[i].getAttribute('data-path');
              if (p === s || p.endsWith('.' + s)) { e = all[i]; break; } } }
          if (e) { e.scrollIntoView({block: 'start'}); return true; }
          return false; })();
        """
    }
}
