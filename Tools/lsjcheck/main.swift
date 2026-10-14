import Foundation
import SQLite3
let s = LexiconStore(databaseURL: URL(fileURLWithPath: CommandLine.arguments[1]))
let lat = LexiconStore(databaseURL: URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/Lexicon/lat.sqlite"))
var fails = 0
func check(_ ok: Bool, _ msg: String) { print(ok ? "PASS" : "FAIL", msg); if !ok { fails += 1 } }
func lsjGender(_ lemma: String) async -> String? {
  let a = await s.article(language: .greek, lemmaNorm: MorphPreprocess.greekBase(lemma))
  return a.flatMap { GenderRefiner.lsjGender(fromHTML: $0.html) }
}
Task {
  print(await s.backendDescription())
  do {
    let pipe = ParserPipeline(preferences: ParserPreferences(greekIgnoreAccents: true))
    for w in ["παῖδα", "ἄνδρα"] {
      let res = await pipe.parse(w, language: .greek)
      check(!res.isEmpty && res.allSatisfy { !$0.morphology.contains("indeclform") }, "no indeclform \(w): \(res.map(\.morphology))")
    }
    // stemtags: Morpheus stemtype/derivation codes are hidden (quantity nil, not in morphology)
    for w in ["λόγος", "παῖδα", "τιμᾷ", "ποιεῖ", "ἔλυσα", "ἄνδρα"] {
      let res = await pipe.parse(w, language: .greek)
      let leaked = res.filter { $0.quantity != nil || $0.morphology.range(of: #"\b[a-z0-9]+_[a-z0-9_,]+\b|\baor1\b|\billw\b"#, options: .regularExpression) != nil }
      check(!res.isEmpty && leaked.isEmpty, "stemtags hidden \(w): \(res.map { "\($0.morphology) | \($0.quantity ?? "-")" })")
    }
    // oidacase: plain / Beta Code / Unicode Greek, in Greek and Both modes
    for lang in [Language.greek, .both] {
      for (w, lemma) in [("oida", "οἶδα"), ("oi)=da", "οἶδα"), ("οἶδα", "οἶδα"), ("ei)de/nai", "οἶδα"), ("h)=n", "εἰμί")] {
        let res = await pipe.parse(w, language: lang)
        check(res.contains { $0.lemma == lemma }, "oidacase \(lang) \(w) → \(lemma): \(res.map(\.lemma))")
      }
    }
    do {
      let a = await pipe.parse("amo", language: .both)
      check(!a.isEmpty && a.allSatisfy { $0.language == .latin }, "both amo stays Latin: \(a.map(\.lemma))")
      let hb = await s.headwords(matching: "oida", searchLanguage: .both, limit: 10)
      check(hb.contains { $0.lemma == "οἶδα" }, "both headwords oida → οἶδα: \(hb.map(\.lemma))")
      let hg = await s.headwords(matching: "oida", searchLanguage: .greek, limit: 10)
      check(hg.contains { $0.lemma == "οἶδα" }, "greek headwords oida → οἶδα")
      let art = await s.article(language: .greek, lemmaNorm: MorphPreprocess.greekBase("οἶδα"))
      check(art != nil, "LSJ article οἶδα")
      // xrefcase: "v. *ei)/dw" renders as Greek and links to εἴδω (rowid 97732, not εἰδώ 97733)
      let h = art?.html ?? ""
      check(!h.contains("*ei)/dw") && (h.contains(">Εἴδω</a>") || h.contains(">εἴδω</a>")), "xrefcase οἶδα shows Greek xref link")
      check(h.contains("href=\"verba-xref:grc?l="), "xrefcase οἶδα href scheme")
      let x1 = await s.resolveCrossReference(lemma: "Εἴδω")
      check(x1?.rowID == 97732, "xrefcase Εἴδω → 97732: \(String(describing: x1?.rowID)) \(x1?.lemma ?? "")")
      let x2 = await s.resolveCrossReference(lemma: "εἰδώ")
      check(x2?.rowID == 97733, "xrefcase εἰδώ → 97733: \(String(describing: x2?.rowID))")
      let x3 = await s.resolveCrossReference(lemma: "λογάς", homograph: 2)
      let x3a = await s.resolveCrossReference(lemma: "λογάς", homograph: 1)
      check(x3 != nil && x3a != nil && x3?.rowID != x3a?.rowID, "xrefcase homograph pick λογάς¹/² \(String(describing: x3a?.rowID)) \(String(describing: x3?.rowID))")
      if let e = await s.resolveCrossReference(lemma: "εἴδω"), let ea = await s.article(for: e) {
        check(ea.html.contains(">οἶδα</span>") && !ea.html.contains("oi)=da"), "xrefcase εἴδω keeps inner orth οἶδα as Greek")
        check(ea.html.contains("(ϝ)εῖδος"), "xrefcase digamma (ϝ)εῖδος")
      } else { check(false, "xrefcase εἴδω article") }
      // seccase: "v. Εἴδω B." links to εἴδω section B and the anchor exists
      if let href = h.range(of: #"href="verba-xref:[^"]*""#, options: .regularExpression).map({ String(h[$0].dropFirst(6).dropLast()) }),
         let url = URL(string: href.replacingOccurrences(of: "&amp;", with: "&")),
         let link = CrossReferenceLink(url: url) {
        check(link.section == "B", "seccase οἶδα link section B: \(link.section ?? "nil")")
        let tgt = await s.resolveCrossReference(lemma: link.lemma, homograph: link.homograph)
        check(tgt?.rowID == 97732, "seccase link target 97732")
        if let tgt, let ta = await s.article(for: tgt) {
          check(ta.html.contains(#"id="sec-B""#), "seccase εἴδω has anchor sec-B")
          check(CrossReferenceLink.scrollScript(section: "B").contains("'sec-'"), "seccase scroll script")
        }
      } else { check(false, "seccase parse οἶδα href") }
      // polcase: LSJ xref display policy
      check(h.contains(">εἴδω</a>") && h.contains("&amp;s=B"), "polcase οἶδα shows linked 'εἴδω' + section B")
      func lsj(_ id: Int64) async -> String {
        await s.article(for: HeadwordHit(lemma: "", lemmaNorm: "", language: .greek, rowID: id))?.html ?? ""
      }
      let heph = await lsj(36574)
      check(heph.contains(">Ἥφαιστος</a>"), "polcase Ἥφαιστος stays capitalized (μετωνυμικός)")
      let nis = await lsj(40180)
      check(nis.contains(#"<span class="xref-plain" lang="greek">νίσῃ</span>"#) && !nis.contains(">νίσῃ</a>"), "polcase νίσσομαι → νίσῃ plain text")
      // qtycase: TLL-style Latin quantity (macrons only; anceps kept)
      check(LatinQuantity.display("ăbactor") == "abactor", "qtycase ăbactor → abactor")
      check(LatinQuantity.display("custōdĭa") == "custōdia", "qtycase custōdĭa → custōdia")
      check(LatinQuantity.display("ămo") == "amo", "qtycase ămo → amo")
      check(LatinQuantity.display("ăcădēmī^a") == "acadēmī̆a".precomposedStringWithCanonicalMapping, "qtycase anceps ī^ → ī̆: \(LatinQuantity.display("ăcădēmī^a"))")
      check(LatinQuantity.display("ă_") == "ă̄".precomposedStringWithCanonicalMapping, "qtycase anceps ă_ → ă̄")
      check(LatinQuantity.display("discŏï_des") == "discoï̄des".precomposedStringWithCanonicalMapping, "qtycase ï_ → ï̄ (macron kept): \(LatinQuantity.display("discŏï_des"))")
      check(LatinQuantity.display("Ăbўla") == "Abyla", "qtycase Cyrillic ў → y")
      check(LatinQuantity.display("λόγος") == "λόγος" && LatinQuantity.display("ᾰ") == "ᾰ", "qtycase Greek untouched")
      for (q, want, mustHave) in [("abactor", "abactor", "ōris"), ("custos", "custos", "ōdis"), ("custodia", "custōdia", ""), ("amo", "amo", "")] {
        let hw = await lat.headwords(matching: q, searchLanguage: .latin, limit: 5)
        let hit = hw.first { $0.lemmaNorm == q }
        check(hit?.displayLemma == want, "qtycase headword \(q) → \(hit?.displayLemma ?? "nil")")
        if let hit, let a = await lat.article(for: hit) {
          let h1 = a.html.range(of: #"<h1[^>]*>[^<]*</h1>"#, options: .regularExpression).map { String(a.html[$0]) } ?? ""
          check(h1.contains(">\(want)<") && (mustHave.isEmpty || a.html.contains(mustHave)), "qtycase article \(q): \(h1) \(mustHave)")
          let headEnd = a.html.range(of: "(")?.lowerBound ?? a.html.endIndex
          check(!a.html[..<headEnd].contains("\u{0306}") && !a.html[..<headEnd].contains("ă"), "qtycase \(q) lemma line has no breves")
        } else { check(false, "qtycase article \(q)") }
      }
      if let ab = await lat.headwords(matching: "abicio", searchLanguage: .latin, limit: 5).first, let a = await lat.article(for: ab) {
        check(a.html.contains("ăbĭci"), "qtycase body citation breves kept (ăbĭci, Ov.)")
        check(ab.displayLemma == "abicio", "qtycase abicio headword \(ab.displayLemma)")
      }
      // maccase: no macron may be lost by the Latin display transform — every L&S row
      do {
        func mac(_ x: String) -> Int { x.decomposedStringWithCanonicalMapping.unicodeScalars.filter { $0 == "\u{0304}" }.count }
        let latPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Resources/Lexicon/lat.sqlite"
        var db: OpaquePointer?; var st: OpaquePointer?
        sqlite3_open_v2(latPath, &db, SQLITE_OPEN_READONLY, nil)
        sqlite3_prepare_v2(db, "select lemma, html_zstd from articles where lang='lat'", -1, &st, nil)
        var rows = 0, lemLoss = 0, htmlLoss = 0, firstBad = ""
        while sqlite3_step(st) == SQLITE_ROW {
          rows += 1
          let lemma = String(cString: sqlite3_column_text(st, 0))
          if mac(LatinQuantity.display(lemma)) < mac(lemma) + (lemma.contains("_") ? lemma.filter { $0 == "_" }.count : 0) {
            lemLoss += 1; if firstBad.isEmpty { firstBad = lemma }
          }
          let data = Data(bytes: sqlite3_column_blob(st, 1), count: Int(sqlite3_column_bytes(st, 1)))
          if let raw = ZstdCodec.decompress(data, dictionary: nil).flatMap({ String(data: $0, encoding: .utf8) }),
             mac(LatinQuantity.displayHTML(raw)) < mac(raw) { htmlLoss += 1; if firstBad.isEmpty { firstBad = lemma } }
        }
        sqlite3_finalize(st); sqlite3_close(db)
        check(rows > 50000 && lemLoss == 0 && htmlLoss == 0, "maccase all \(rows) L&S headwords/articles keep every macron (lemma \(lemLoss), html \(htmlLoss)) \(firstBad)")
        check(LatinQuantity.display("a\u{0306}_") == "ă̄".precomposedStringWithCanonicalMapping && LatinQuantity.display("ā^") == "ā̆".precomposedStringWithCanonicalMapping && LatinQuantity.display("ăcădēmī^a") == "acadēmī̆a".precomposedStringWithCanonicalMapping, "maccase L&S anceps ă_ → ă̄, ā^ → ā̆ (acadēmī̆a)")
        check(LatinQuantity.display("discŏï_des") == "discoï̄des".precomposedStringWithCanonicalMapping, "maccase bare _ after ï → macron: \(LatinQuantity.display("discŏï_des"))")
        check(LatinQuantity.bodyDisplay("cf. ăbĭci, allā^crў-mo, ă_fri") == "cf. ăbĭci, allā̆cry̆-mo, ă̄fri".precomposedStringWithCanonicalMapping, "maccase body markers rendered, breves kept: \(LatinQuantity.bodyDisplay("cf. ăbĭci, allā^crў-mo, ă_fri"))")
        let abA = await lat.headwords(matching: "abdico", searchLanguage: .latin, limit: 5).filter { $0.lemmaNorm == "abdico" }
        check(abA.map(\.displayLemma) == ["ab-dico", "ab-dīco"], "maccase pane lists both ab-dĭco / ab-dīco: \(abA.map(\.displayLemma))")
        check(LatinQuantity.display("βα^ρύς") == "βᾰρύς".precomposedStringWithCanonicalMapping && LatinQuantity.bodyDisplay("Σῖκα^νοί") == "Σῖκᾰνοί".precomposedStringWithCanonicalMapping, "maccase Greek ^ in L&S → ᾰ")
        let ci = await lat.headwords(matching: "cito", searchLanguage: .latin, limit: 10).filter { $0.lemmaNorm == "cito" }.map(\.displayLemma)
        check(ci == ["cito¹", "cito²"], "maccase breve-only L&S homographs numbered: \(ci)")
        let ciP = await ParserPipeline(preferences: ParserPreferences()).parse("cito", language: .latin)
        var ciL: [String] = []; for a in ciP { ciL.append(await lat.headwordLabel(for: a) ?? "nil") }
        check(ciL.contains("cito¹") && ciL.contains("cito²") && !ciL.contains { $0.decomposedStringWithCanonicalMapping.contains("\u{0306}") }, "maccase analyses show L&S headword, no breves: \(ciL)")
        for (raw, want) in [("consú^ētē","cōnsuētē"),("dēstrictárĭum","dēstrictārium"),("augùrālis","augurālis"),("augùrātĭo","augurātio"),("circum-tuèŏr","circum-tueor")] {
          check(LatinQuantity.display(raw) == want.precomposedStringWithCanonicalMapping, "tllfix \(raw) → \(LatinQuantity.display(raw))")
        }
        if let e = await lat.headwords(matching: "erythea", searchLanguage: .latin, limit: 5).first(where: { $0.lemma.contains("thēa") }), let a = await lat.article(for: e) {
          check(!a.html.contains("-_ia") && a.html.contains("-ia"), "tllfix Ĕrўthēa stray _ dropped")
        } else { check(false, "tllfix Erythea article") }
        for (raw, want) in [("cŭbo ŭi, ìtúm","cubo ui, itum"),("multĭ-fer féra","multi-fer fera"),("abscído","abscīdo"),("nătātìcĭus","natāticius"),("variatione ullà","variatione ullā")] {
          check(LatinQuantity.display(raw) == want.precomposedStringWithCanonicalMapping, "tllfix2 \(raw) → \(LatinQuantity.display(raw))")
        }
        let ery = await lat.headwords(matching: "erythea", searchLanguage: .latin, limit: 5)
        check(ery.contains { $0.lemma.contains("thēa") }, "ў key: erythea finds Ĕrўthēa: \(ery.map(\.displayLemma))")
        let abd = await lat.headwords(matching: "abdalonymus", searchLanguage: .latin, limit: 5)
        check(!abd.isEmpty, "ў key: abdalonymus: \(abd.map(\.displayLemma))")
        check(ciP.contains { $0.pos == "participle" } && ciP.contains { $0.pos == "adverb" }, "pos: cito → participle (cieo) + adverb: \(ciP.map(\.pos))")
        let ciO = ParserPipeline.exactLemmaFirst(ciP, query: "cito").map { "\($0.lemma)/\($0.pos)" }
        check(ciO.count == ciP.count && ciO.prefix(2).allSatisfy { $0.hasPrefix("cito/") } && Set(ciO.prefix(2)) == ["cito/adverb", "cito/verb"], "order: exact lemma first for cito: \(ciO)")
        let lgO = ParserPipeline.exactLemmaFirst(await ParserPipeline(preferences: ParserPreferences()).parse("λόγου", language: .greek), query: "λόγου").map(\.lemma)
        check(!lgO.isEmpty, "order: greek no-exact keeps order: \(lgO)")
        let abP = await ParserPipeline(preferences: ParserPreferences()).parse("abdico", language: .latin)
        var abArts: [String] = []
        for a in abP { if let art = await lat.article(for: a) { abArts.append("\(await lat.headwordLabel(for: a) ?? "nil")→\(art.lemma)") } }
        check(abArts.contains("ab-dico→ab-dico") && abArts.contains("ab-dīco→ab-dīco"), "maccase Morpheus abdico#1/#2 → L&S homographs: \(abArts)")
        check(LatinQuantity.display("ȳ Ȳ Ǣ ǣ ĀĒĪŌŪ") == "ȳ Ȳ Ǣ ǣ ĀĒĪŌŪ", "maccase ȳ Ȳ Ǣ ǣ ĀĒĪŌŪ unchanged")
        let ab = await lat.headwords(matching: "abdico", searchLanguage: .latin, limit: 5).filter { $0.lemmaNorm == "abdico" }
        check(ab.map(\.displayLemma).contains("ab-dīco"), "maccase L&S homograph ab-dīco present: \(ab.map(\.displayLemma))")
        if let abb = await lat.headwords(matching: "abbas", searchLanguage: .latin, limit: 3).first, let a = await lat.article(for: abb) {
          check(a.html.contains("abbātissa"), "maccase inner derivative abbātissa kept in abbās")
        }
      }
      // histcase: Back/Forward restore exact article rows (pure NavigationHistory)
      func stop(_ k: HistoryEntry.Kind, _ q: String, _ hit: HeadwordHit?) async -> HistoryEntry {
        let a: LexiconArticle? = hit != nil ? await s.article(for: hit!) : nil
        return HistoryEntry(kind: k, query: q, language: .greek, analyses: [], selectedAnalysisID: nil,
                            headwords: [], selectedHeadwordID: hit?.id, articleRowID: hit?.rowID, article: a)
      }
      var nav = NavigationHistory()
      let oidaHit = await s.headwords(matching: "oida", searchLanguage: .greek, limit: 5).first
      nav.push(await stop(.search, "oida", oidaHit))
      nav.push(await stop(.crossReference, "oida", await s.resolveCrossReference(lemma: "Εἴδω")))
      let b1 = nav.back()
      check(b1?.article?.lemma == "οἶδα", "histcase back → οἶδα: \(b1?.article?.lemma ?? "nil")")
      let f1 = nav.forward()
      check(f1?.articleRowID == 97732 && f1?.article?.lemma == "εἴδω", "histcase forward → εἴδω 97732: \(String(describing: f1?.articleRowID))")
      let lg = await s.headwords(matching: "logas", searchLanguage: .greek, limit: 10).filter { $0.lemma == "λογάς" }
      var nav2 = NavigationHistory()
      if lg.count >= 2 {
        nav2.push(await stop(.headword, "logas", lg[0]))
        nav2.push(await stop(.headword, "logas", lg[1]))
        check(nav2.entries.count == 2, "histcase λογάς¹/² are two stops (same query)")
        let b = nav2.back(); let f = nav2.forward()
        check(b?.articleRowID == lg[0].rowID && f?.articleRowID == lg[1].rowID, "histcase λογάς¹ ← → λογάς²")
        nav2.push(await stop(.headword, "logas", lg[1]))
        check(nav2.entries.count == 2, "histcase re-open same row is not a new stop")
        _ = nav2.back(); nav2.push(await stop(.headword, "logas", lg[1]))
        check(nav2.entries.count == 2 && !nav2.canGoForward, "histcase push after Back truncates forward")
      } else { check(false, "histcase λογάς homographs \(lg.count)") }
    }
    for w in ["τιμᾷ", "ποιεῖ"] {
      let res = await pipe.parse(w, language: .greek)
      let ms = res.map(\.morphology)
      check(ms.contains { $0.contains("contr.") } && !ms.contains { $0.range(of: #"\bcontr\b(?!\.)"#, options: .regularExpression) != nil }, "contr. \(w): \(ms)")
    }
  }
  for (w, want) in [("λόγος","ὁ"),("ἀνήρ","ὁ"),("ἡμέρα","ἡ"),("δῶρον","τό"),("παῖς","ὁ, ἡ"),("θεός","ὁ")] {
    let g = await lsjGender(w); check(g == want, "gender \(w) = \(g ?? "nil") (want \(want))")
  }
  // Refinement applied to a Morpheus-style analysis
  let a = Analysis(lemma: "παῖς", lemmaNorm: "παις", language: .greek, pos: "noun", morphology: "masc/fem nom sg")
  let art = await s.article(for: a)
  let r = GenderRefiner.refine(a, articleHTML: art?.html)
  check(r.morphology == "ὁ, ἡ nom sg", "refine παῖς masc/fem → \(r.morphology)")
  let b = Analysis(lemma: "λόγος", lemmaNorm: "λογος", language: .greek, pos: "noun", morphology: "masc nom sg")
  let rb = GenderRefiner.refine(b, articleHTML: await s.article(for: b)?.html)
  check(rb.morphology == "ὁ nom sg", "refine λόγος masc → \(rb.morphology)")
  // Superscripts
  let h1 = await s.headwords(matching: "λογάς", searchLanguage: .greek, limit: 10).filter { $0.lemma == "λογάς" }
  check(h1.map(\.displayLemma) == ["λογάς¹","λογάς²"], "hw λογάς \(h1.map(\.displayLemma))")
  let h2 = await s.headwords(matching: "ὅ", searchLanguage: .greek, limit: 200).filter { $0.lemma == "ὅ" }
  check(h2.map(\.displayLemma) == ["ὅ¹","ὅ²","ὅ³"], "hw ὅ \(h2.map(\.displayLemma))")
  let h3 = await s.headwords(matching: "λόγος", searchLanguage: .greek, limit: 10).filter { $0.lemma == "λόγος" }
  check(h3.map(\.displayLemma) == ["λόγος"], "hw λόγος unique \(h3.map(\.displayLemma))")
  let hl = await s.headwords(matching: "custod", searchLanguage: .latin, limit: 20)
  check(hl.allSatisfy { $0.homographNumber == nil }, "latin custod no superscripts \(hl.map(\.displayLemma))")
  // Homograph pick for analysis: first in LSJ order
  let e = await s.article(language: .greek, lemmaNorm: "ειμι"); print("ειμι →", e?.lemma ?? "MISS")
  // Latin
  let c = Analysis(lemma: "custos", lemmaNorm: "custos", language: .latin, pos: "noun", morphology: "masc/fem acc pl")
  let rc = GenderRefiner.refine(c, articleHTML: await s.article(for: c)?.html)
  check(rc.morphology.contains("comm."), "latin custodes → \(rc.morphology)")
  let am = await s.article(language: .latin, lemmaNorm: "amo"); check(am != nil, "latin amo article \(am?.lemma ?? "MISS")")
  // End-to-end: Morpheus (cruncher) → LSJ gender refine, no GUI.
  let pipe = ParserPipeline(preferences: ParserPreferences(greekIgnoreAccents: false))
  for (form, want) in [("λόγος","ὁ"),("ἄνδρα","ὁ"),("ἡμέραν","ἡ"),("δῶρα","τό"),("παῖδα","ὁ, ἡ")] {
    let res = await pipe.parse(form, language: .greek)
    var lines: [String] = []
    for a in res { let art = await s.article(for: a); lines.append("\(a.lemma): " + GenderRefiner.refine(a, articleHTML: art?.html).morphology) }
    check(lines.contains { $0.contains(want) }, "e2e \(form) → \(lines)")
    check(!res.contains { $0.lemma.hasSuffix("σ") }, "final ς in lemmas for \(form): \(res.map(\.lemma))")
  }
  for (b, want) in [("lo/gos","λόγος"),("pai=s","παῖς"),("sw=ma","σῶμα"),("lo/gos kai\\ e)/pos","λόγος καὶ ἔπος")] {
    let d = BetaCode.toDisplay(b); check(d == want, "toDisplay \(b) → \(d)")
  }
  let hp = await s.headwords(matching: "pas", searchLanguage: .greek, limit: 300)
  check(hp.contains { $0.lemma.hasPrefix("πᾶσ") } && hp.contains { $0.lemma == "πᾶς" }, "hw pas lists πᾶς and πᾶσ… (\(hp.count))")
  check(ParserPreferences().greekIgnoreAccents, "-n default on")
  let pd = ParserPipeline(preferences: ParserPreferences())
  let un = await pd.parse("λογος", language: .greek)
  check(un.contains { $0.lemma == "λόγος" }, "unaccented λογος parses with default prefs: \(un.map(\.lemma))")
  // antiochos: pasted NFC / NFD / oxia / invisible-char Ἀντίοχος → headwords + analyses
  let antNFC = "Ἀντίοχος".precomposedStringWithCanonicalMapping
  for (tag, w) in [("NFC", antNFC), ("NFD", antNFC.decomposedStringWithCanonicalMapping),
                   ("oxia", antNFC.replacingOccurrences(of: "\u{03AF}", with: "\u{1F77}")),
                   ("LRM", "\u{200E}" + antNFC + "\u{200B}")] {
    let hw = await s.headwords(matching: w, searchLanguage: .greek, limit: 80)
    let hwPre = await s.headwords(matching: w.replacingOccurrences(of: "ος", with: ""), searchLanguage: .greek, limit: 80)
    let res = await pd.parse(w, language: .greek)
    check(!hwPre.isEmpty && res.contains { $0.lemma.hasPrefix("Ἀντ") }, "antiochos \(tag): hw=\(hw.map(\.lemma)) hwPrefix=\(hwPre.prefix(3).map(\.lemma)) parse=\(res.map(\.lemma))")
  }
  check(BetaCode.fromGreek("Ἀντίοχος") == "*)anti/oxos", "fromGreek capital order: \(BetaCode.fromGreek("Ἀντίοχος"))")
  check(BetaCode.toDisplay("*)anti/oxos") == "Ἀντίοχος" && BetaCode.toDisplay("*a)nti/oxos") == "Ἀντίοχος", "toDisplay capital both orders")
  print(fails == 0 ? "ALL PASS" : "\(fails) FAIL"); exit(fails == 0 ? 0 : 1)
}
RunLoop.main.run()
