import Foundation
import SQLite3
// Headless L&S macron audit: raw orth vs headword pane, article head, analysis label.
let latPath = CommandLine.arguments[1]
let store = LexiconStore(databaseURL: URL(fileURLWithPath: latPath))
let M: Unicode.Scalar = "\u{0304}", B: Unicode.Scalar = "\u{0306}"
func sc(_ s: String) -> [Unicode.Scalar] { Array(s.decomposedStringWithCanonicalMapping.unicodeScalars) }
// Expected long marks: macrons + bare `_` (ă_ counts once: the macron it gains).
func longs(_ s: String) -> Int { sc(s).filter { $0 == M || $0 == "_" }.count }
func mac(_ s: String) -> Int { sc(s).filter { $0 == M }.count }
func strip(_ s: String) -> String { s.replacingOccurrences(of: #"[¹²³⁴⁵⁶⁷⁸⁹⁰]+$"#, with: "", options: .regularExpression) }
func headText(_ html: String) -> String {
  // text of <h1>…</h1> or first 200 chars of text
  let t = html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
  return String(t.prefix(120))
}
var db: OpaquePointer?; var st: OpaquePointer?
sqlite3_open_v2(latPath, &db, SQLITE_OPEN_READONLY, nil)
sqlite3_prepare_v2(db, "select id, lemma, lemma_norm from articles where lang='lat' order by id", -1, &st, nil)
var rows: [(Int64, String, String)] = []
while sqlite3_step(st) == SQLITE_ROW {
  rows.append((sqlite3_column_int64(st, 0), String(cString: sqlite3_column_text(st, 1)), String(cString: sqlite3_column_text(st, 2))))
}
var classes: [String: [String]] = [:]
func add(_ k: String, _ ex: String) { classes[k, default: []].append(ex) }
var byNorm: [String: [(Int64, String)]] = [:]
let homs = SQLiteLexiconDB(url: URL(fileURLWithPath: latPath))!.homographNumbers()
Task {
  for (id, lemma, norm) in rows {
    byNorm[norm, default: []].append((id, lemma))
    let hit = HeadwordHit(lemma: lemma, lemmaNorm: norm, language: .latin, rowID: id, homographNumber: homs[id])
    let pane = strip(hit.displayLemma)
    if mac(pane) < longs(lemma) { add("pane-lost-macron", "\(lemma) → \(pane)") }
    if pane.contains(where: { "_^".contains($0) }) { add("pane-residual-_^", "\(lemma) → \(pane)") }
    if pane.unicodeScalars.contains(where: { (0x0400...0x04FF).contains($0.value) }) { add("pane-cyrillic", "\(lemma) → \(pane)") }
    if sc(pane).contains(where: { $0 == B }) && !(sc(lemma).contains("^") || sc(lemma).contains("_")) { add("pane-breve-kept", "\(lemma) → \(pane)") }
    if let art = await store.article(for: hit) {
      if art.lemma != pane && strip(art.lemma) != pane { add("article-lemma≠pane", "\(lemma): pane \(pane) / art \(art.lemma)") }
      // first occurrence of the headword text in the head
      let rawHead = headText(art.html)
      if rawHead.contains("_") || rawHead.contains("^") { if let r = rawHead.firstIndex(where: { "_^".contains($0) }) { let lo = rawHead.index(r, offsetBy: -8, limitedBy: rawHead.startIndex) ?? rawHead.startIndex; let hi = rawHead.index(r, offsetBy: 6, limitedBy: rawHead.endIndex) ?? rawHead.endIndex; add("head-residual-_^", "\(lemma): …\(rawHead[lo..<hi])…") } }
    } else { add("no-article", lemma) }
  }
  // homographs: same norm, several rows
  for (norm, list) in byNorm where list.count > 1 {
    let labels = list.map { r in HeadwordHit(lemma: r.1, lemmaNorm: norm, language: .latin, rowID: r.0, homographNumber: homs[r.0]).displayLemma }
    if Set(labels).count < labels.count { add("homograph-labels-identical", "\(norm): \(labels)") }
    let rawDistinct = Set(list.map(\.1)).count == list.count
    let shown = Set(list.map { LatinQuantity.display($0.1) })
    if rawDistinct && shown.count < list.count { add("homographs-merge-after-breve-drop (no superscript)", "\(norm): \(list.map(\.1)) → \(shown.sorted())") }
    let hits = await store.headwords(matching: norm, searchLanguage: .latin, limit: 500).filter { $0.lemmaNorm == norm }
    if hits.count != list.count { add("pane-missing-homograph", "\(norm): db \(list.count) pane \(hits.count)") }
  }
  for (k, v) in classes.sorted(by: { $0.value.count > $1.value.count }) {
    print("\(v.count)\t\(k)"); for e in v.prefix(30) { print("\t\(e)") }
  }
  print("rows \(rows.count)"); exit(0)
}
RunLoop.main.run()
