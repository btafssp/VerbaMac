import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Weak handle to the lexicon web view so the toolbar can read the current selection.
@MainActor
final class LexiconWebViewHandle {
    static let shared = LexiconWebViewHandle()
    weak var webView: WKWebView?
}

/// Toolbar Share button (NSSharingServicePicker). Shares the selected lexicon text, or the whole
/// article when nothing is selected, as RTF + HTML with a plain-text fallback, headed by the bold lemma.
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
    }

    @MainActor
    final class Coordinator: NSObject {
        var article: LexiconArticle?

        private static let selectionScript = """
        (function(){
          var s = window.getSelection();
          if (s && s.rangeCount && !s.isCollapsed && s.toString().trim().length > 0) {
            var d = document.createElement('div');
            for (var i = 0; i < s.rangeCount; i++) d.appendChild(s.getRangeAt(i).cloneContents());
            return {html: d.innerHTML, text: s.toString()};
          }
          return {html: document.body.innerHTML, text: document.body.innerText};
        })()
        """

        @objc func share(_ sender: NSButton) {
            guard let article, let webView = LexiconWebViewHandle.shared.webView else { return }
            webView.evaluateJavaScript(Self.selectionScript) { result, _ in
                guard let dict = result as? [String: Any],
                      let html = dict["html"] as? String,
                      let text = dict["text"] as? String else { return }
                MainActor.assumeIsolated {
                    Self.present(html: html, text: text, lemma: article.lemma,
                                 source: Self.sourceName(article.language), from: sender)
                }
            }
        }

        static func sourceName(_ language: LexiconLanguage) -> String {
            switch language {
            case .latin: return "Lewis & Short, A Latin Dictionary (Perseus Digital Library)"
            case .greek: return "Liddell, Scott & Jones, A Greek–English Lexicon (Perseus Digital Library)"
            }
        }

        private static func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
        }

        static func present(html: String, text: String, lemma: String, source: String, from view: NSView) {
            let doc = """
            <!DOCTYPE html><html><head><meta charset="utf-8"></head><body>\
            <p><b>\(escape(lemma))</b></p>\(html)<p><i>— \(escape(source))</i></p></body></html>
            """
            let plain = lemma + "\n\n" + text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n— " + source

            let htmlData = Data(doc.utf8)
            var rtfData: Data?
            if let attributed = try? NSAttributedString(
                data: htmlData,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil) {
                rtfData = try? attributed.data(from: NSRange(location: 0, length: attributed.length),
                                               documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
            }

            let provider = NSItemProvider()
            if let rtfData {
                provider.registerDataRepresentation(forTypeIdentifier: UTType.rtf.identifier, visibility: .all) { done in
                    done(rtfData, nil); return nil
                }
            }
            provider.registerDataRepresentation(forTypeIdentifier: UTType.html.identifier, visibility: .all) { done in
                done(htmlData, nil); return nil
            }
            provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { done in
                done(Data(plain.utf8), nil); return nil
            }
            provider.suggestedName = lemma

            NSSharingServicePicker(items: [provider]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }
}
