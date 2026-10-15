import AppKit
import SwiftUI
import WebKit

/// Lexicon web view handle, live selection, and a precomputed whole-article share item.
/// The selection arrives through a `selectionchange` script bridge and the article payload
/// is built ahead of time, so the Share click can open the picker synchronously
/// (NSSharingServicePicker must be shown within the user-gesture turn).
@MainActor
final class LexiconWebViewHandle {
    static let shared = LexiconWebViewHandle()
    static let selectionMessage = "lexiconSelection"

    weak var webView: WKWebView?
    var selectionHTML = ""
    var selectionText = ""
    var hasSelection: Bool { !selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private(set) var articleID: UUID?
    private(set) var articleItem: NSAttributedString?

    func clearSelection() {
        selectionHTML = ""
        selectionText = ""
    }

    func prepare(article: LexiconArticle) {
        guard articleID != article.id || articleItem == nil else { return }
        articleID = article.id
        articleItem = LexiconSharePayload.attributed(lemma: article.lemma, bodyHTML: article.html,
                                                     language: article.language)
    }

    func clearArticle() {
        articleID = nil
        articleItem = nil
        clearSelection()
    }

    /// JavaScript posting the current selection (HTML + text) on every change.
    static let selectionScript = """
    document.addEventListener('selectionchange', function () {
      var s = window.getSelection();
      var h = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\(selectionMessage);
      if (!h) return;
      if (!s || !s.rangeCount || s.isCollapsed || !s.toString().trim()) { h.postMessage({html: '', text: ''}); return; }
      var d = document.createElement('div');
      for (var i = 0; i < s.rangeCount; i++) d.appendChild(s.getRangeAt(i).cloneContents());
      h.postMessage({html: d.innerHTML, text: s.toString()});
    });
    """
}

enum LexiconSharePayload {
    static func credit(for language: LexiconLanguage) -> String {
        switch language {
        case .latin: return "Lewis & Short, A Latin Dictionary (Perseus Digital Library)"
        case .greek: return "Liddell, Scott & Jones, A Greek–English Lexicon (Perseus Digital Library)"
        }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// One attributed string: body (which already starts with the lemma), blank line, italic credit.
    /// Share services read RTF, HTML, and plain text from it.
    static func attributed(lemma: String, bodyHTML: String, language: LexiconLanguage) -> NSAttributedString? {
        let doc = """
        <!DOCTYPE html><html><head><meta charset="utf-8"></head><body>\
        \(bodyHTML)<p><br></p><p><i>— \(escape(credit(for: language)))</i></p></body></html>
        """
        guard let data = doc.data(using: .utf8),
              let attr = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil),
              attr.length > 0 else { return nil }
        return attr
    }
}

/// Toolbar Share button: the selected lexicon text, or the whole article when nothing is selected.
struct LexiconShareButton: NSViewRepresentable {
    let article: LexiconArticle?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSButton {
        let image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share") ?? NSImage()
        let button = NSButton(image: image, target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .texturedRounded
        button.toolTip = "Share selection or article"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.article = article
        button.isEnabled = article != nil
        if let article {
            Task { @MainActor in LexiconWebViewHandle.shared.prepare(article: article) }
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var article: LexiconArticle?

        @objc func share(_ sender: NSButton) {
            guard let article else { return }
            let handle = LexiconWebViewHandle.shared
            let item: NSAttributedString?
            if handle.hasSelection {
                item = LexiconSharePayload.attributed(lemma: article.lemma, bodyHTML: handle.selectionHTML,
                                                      language: article.language)
            } else {
                handle.prepare(article: article)
                item = handle.articleItem
            }
            guard let item else { NSSound.beep(); return }
            NSSharingServicePicker(items: [item]).show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }
}
