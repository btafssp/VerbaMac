import SwiftUI
import WebKit
import AppKit

/// Bottom pane: lexicon article HTML via WKWebView + in-article Find bar.
struct ArticleView: View {
    @ObservedObject var state: AppState
    let article: LexiconArticle?
    var statusMessage: String?
    var colorScheme: LexiconColorScheme = .softDark
    /// Body base points shared with analyses pane (UserDefaults / Cmd+/-).
    var contentTextSize: Double = ContentTextSize.defaultPoints
    /// When true, WKWebView becomes first responder for scrolling.
    var lexiconFocused: Bool = false
    /// Shift-Tab from lexicon → analyses pane.
    var onShiftTab: () -> Void = {}

    var body: some View {
        VStack(spacing: 0) {
            if state.showArticleFindBar {
                articleFindBar
                Divider()
            }

            Group {
                if let article {
                    ArticleWebView(
                        html: Self.wrappedHTML(
                            article.html,
                            scheme: colorScheme,
                            bodyPoints: contentTextSize
                        ),
                        wantsKeyboardFocus: lexiconFocused && !state.showArticleFindBar,
                        onShiftTab: onShiftTab,
                        onEscape: { if state.showArticleFindBar { state.closeArticleFind(returnFocusToLexicon: true) } },
                        findString: state.articleFindString,
                        findCommand: state.articleFindCommand,
                        onCapturedSelection: { state.applyCapturedFindSelection($0) },
                        scrollSection: state.articleSection,
                        onCrossReference: { state.openCrossReference($0) }
                    )
                } else {
                    emptyLexicon
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(schemeBackdrop)
    }

    private var articleFindBar: some View {
        HStack(spacing: 8) {
            FindField(
                text: state.articleFindString,
                focusToken: state.findFieldFocusToken,
                focusOnAppear: { state.consumeFindFocusPending() },
                onChange: { state.updateArticleFindString($0) },
                onSubmit: { state.findNextInArticle() },
                onEscape: { state.closeArticleFind(returnFocusToLexicon: true) }
            )
            .frame(maxWidth: 280)

            Button("Next") { state.findNextInArticle() }
                .disabled(state.articleFindString.isEmpty)
            Button("Previous") { state.findPreviousInArticle() }
                .disabled(state.articleFindString.isEmpty)

            Spacer(minLength: 0)

            Button {
                state.closeArticleFind(returnFocusToLexicon: true)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Close Find")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.bar)
        .onExitCommand { state.closeArticleFind(returnFocusToLexicon: true) }
    }

    private var emptyLexicon: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.system(size: max(24, 36 * ContentTextSize.scale(for: contentTextSize))))
                .foregroundStyle(.secondary)
            Text("Lexicon")
                .font(.system(size: ContentTextSize.headlineSize(contentTextSize), weight: .semibold))
            Text("Select an analysis or headword to load the article.")
                .font(.system(size: ContentTextSize.subheadlineSize(contentTextSize)))
                .foregroundStyle(.secondary)
            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: ContentTextSize.captionSize(contentTextSize)))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var schemeBackdrop: some View {
        if colorScheme == .systemDefault {
            Color.clear
        } else {
            colorScheme.paneBackground
        }
    }

    /// Wrap article HTML with Diogenes-like L&S presentation.
    static func wrappedHTML(
        _ body: String,
        scheme: LexiconColorScheme = .softDark,
        bodyPoints: Double = ContentTextSize.defaultPoints
    ) -> String {
        let px = ContentTextSize.clamp(bodyPoints)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8"/>
        <meta name="viewport" content="width=device-width, initial-scale=1"/>
        <style>
          \(scheme.cssVariables)
          html, body {
            margin: 0; padding: 0;
            font: \(px)px/1.55 -apple-system, BlinkMacSystemFont, "Helvetica Neue",
                  "Times New Roman", "Times", serif;
          }
          article.entry {
            padding: 16px 20px 24px;
            max-width: 52rem;
          }
          h1, h1.orth {
            display: inline;
            font-size: 1.3rem;
            font-weight: 700;
            margin: 0;
            font-family: "Times New Roman", "Times", "Georgia", serif;
          }
          span.itype {
            font-style: normal;
            font-weight: 400;
          }
          span.gen, span.pos, p.pos {
            font-style: italic;
            font-weight: 400;
          }
          p.pos { display: inline; margin: 0; }
          span.etym, p.etym {
            display: inline;
            color: var(--muted, GrayText);
            font-size: 0.95em;
          }
          div.sense {
            display: block;
            padding-bottom: 0.5em;
            margin: 0.2em 0 0;
            overflow: visible;
          }
          div.sense[data-level="1"] { padding-left: 1.25em; }
          div.sense[data-level="2"] { padding-left: 2.25em; }
          div.sense[data-level="3"] { padding-left: 3.25em; }
          div.sense[data-level="4"] { padding-left: 4.25em; }
          div.sense[data-level="5"] { padding-left: 5.25em; }
          span.sense-lead { display: inline; }
          span.sense-n {
            font-weight: 700;
            font-style: normal;
            margin-right: 0.2em;
          }
          article.entry i, article.entry b i {
            font-style: italic;
            font-weight: var(--gloss-weight, 600);
          }
          article.entry b { font-weight: 700; }
          span.tr { font-style: italic; font-weight: var(--gloss-weight, 600); }
          q {
            font-style: normal;
            font-weight: 400;
            quotes: none;
          }
          q::before, q::after { content: none; }
          cite, span.cit cite, span.author {
            font-style: normal;
            font-size: 0.92em;
            color: var(--muted, GrayText);
          }
          span.cit { font-weight: 400; }
          span[lang="greek"], span[lang="grc"], q[lang="greek"], h1[lang="greek"] {
            font-family: "Times New Roman", "Gentium Plus", "Gentium", "New Athena Unicode", "Lucida Grande", serif;
          }
          a.xref {
            color: var(--link, LinkText);
            text-decoration: none;
            font-family: "Times New Roman", "Gentium Plus", "Gentium", "New Athena Unicode", "Lucida Grande", serif;
          }
          a.xref:hover { text-decoration: underline; }
          ol { padding-left: 1.4rem; margin: 0.5rem 0; }
          li { margin: 0.35rem 0; }
          p.note, p.credit {
            margin-top: 1.1rem;
            font-size: 0.8rem;
            color: var(--muted, GrayText);
          }
          pre.plain {
            white-space: pre-wrap;
            font: inherit;
            color: var(--muted, GrayText);
          }
          ::highlight(verba-find) {
            background-color: #ffe566;
            color: #000;
          }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}

#if os(macOS)
/// WKWebView that intercepts Shift-Tab to leave the lexicon pane.
final class LexiconWKWebView: WKWebView {
    var onShiftTab: (() -> Void)?
    var onEscape: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        if let onEscape { onEscape() } else { super.cancelOperation(sender) }
    }

    override func keyDown(with event: NSEvent) {
        if Self.isShiftTab(event) {
            onShiftTab?()
            return
        }
        super.keyDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isShiftTab(event) {
            onShiftTab?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    private static func isShiftTab(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == 48 && flags.contains(.shift) && !flags.contains(.command) && !flags.contains(.option)
    }
}

struct ArticleWebView: NSViewRepresentable {
    let html: String
    var wantsKeyboardFocus: Bool = false
    var onShiftTab: () -> Void = {}
    var onEscape: () -> Void = {}
    var findString: String = ""
    var findCommand: ArticleFindCommand? = nil
    var onCapturedSelection: (String) -> Void = { _ in }
    /// LSJ `<a class="xref" href="verba-xref:grc?l=…&h=…">` clicked.
    /// Section anchor to scroll to after load (or now, when only the section changed).
    var scrollSection: String? = nil
    var onCrossReference: (CrossReferenceLink) -> Void = { _ in }

    func makeNSView(context: Context) -> LexiconWKWebView {
        let config = WKWebViewConfiguration()
        config.suppressesIncrementalRendering = true
        config.userContentController.add(context.coordinator, name: LexiconWebViewHandle.selectionMessage)
        config.userContentController.addUserScript(WKUserScript(
            source: LexiconWebViewHandle.selectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let webView = LexiconWKWebView(frame: .zero, configuration: config)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.onShiftTab = onShiftTab
        context.coordinator.webView = webView
        LexiconWebViewHandle.shared.webView = webView
        return webView
    }

    func updateNSView(_ webView: LexiconWKWebView, context: Context) {
        webView.onShiftTab = onShiftTab
        webView.onEscape = onEscape
        context.coordinator.onCapturedSelection = onCapturedSelection
        context.coordinator.onCrossReference = onCrossReference
        context.coordinator.findString = findString

        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            context.coordinator.pendingSection = scrollSection
            context.coordinator.lastSection = scrollSection
            LexiconWebViewHandle.shared.clearSelection()
            webView.loadHTMLString(html, baseURL: nil)
        } else if context.coordinator.lastSection != scrollSection {
            context.coordinator.lastSection = scrollSection
            webView.evaluateJavaScript(CrossReferenceLink.scrollScript(section: scrollSection), completionHandler: nil)
        }

        if wantsKeyboardFocus {
            if !context.coordinator.isFirstResponder {
                context.coordinator.isFirstResponder = true
                DispatchQueue.main.async {
                    webView.window?.makeFirstResponder(webView)
                }
            }
        } else if context.coordinator.isFirstResponder {
            context.coordinator.isFirstResponder = false
        }

        if let cmd = findCommand, context.coordinator.lastHandledFindID != cmd.id {
            context.coordinator.lastHandledFindID = cmd.id
            context.coordinator.handle(cmd, in: webView)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    static func dismantleNSView(_ webView: LexiconWKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: LexiconWebViewHandle.selectionMessage)
        if LexiconWebViewHandle.shared.webView === webView {
            LexiconWebViewHandle.shared.webView = nil
            LexiconWebViewHandle.shared.clearArticle()
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == LexiconWebViewHandle.selectionMessage,
                  let body = message.body as? [String: Any] else { return }
            LexiconWebViewHandle.shared.selectionHTML = body["html"] as? String ?? ""
            LexiconWebViewHandle.shared.selectionText = body["text"] as? String ?? ""
        }

        var lastHTML: String?
        var isFirstResponder = false
        var lastHandledFindID: UUID?
        var findString: String = ""
        var onCapturedSelection: (String) -> Void = { _ in }
        var onCrossReference: (CrossReferenceLink) -> Void = { _ in }
        weak var webView: LexiconWKWebView?
        var pendingSection: String?
        var lastSection: String?

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let section = pendingSection else { return }
            pendingSection = nil
            webView.evaluateJavaScript(CrossReferenceLink.scrollScript(section: section), completionHandler: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            guard navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            // Article links never navigate the web view away from the article.
            decisionHandler(.cancel)
            if let link = CrossReferenceLink(url: url) {
                onCrossReference(link)
            }
        }

        func handle(_ cmd: ArticleFindCommand, in webView: LexiconWKWebView) {
            switch cmd.kind {
            case .focusBar:
                break
            case .find(let backwards):
                runFind(in: webView, backwards: backwards)
            case .useSelection:
                captureSelection(in: webView)
            case .jumpToSelection:
                jumpToSelection(in: webView)
            case .clearHighlights:
                let js = "(function(){ try { window.getSelection().removeAllRanges(); if (window.CSS && CSS.highlights) CSS.highlights.clear(); } catch(e) {} })();"
                webView.evaluateJavaScript(js, completionHandler: nil)
            }
        }

        private func runFind(in webView: LexiconWKWebView, backwards: Bool) {
            let needle = findString
            guard !needle.isEmpty else { return }
            let config = WKFindConfiguration()
            config.backwards = backwards
            config.caseSensitive = false
            config.wraps = true
            webView.find(needle, configuration: config) { _ in
                // Match is selected + scrolled by WebKit when found.
            }
        }

        private func captureSelection(in webView: LexiconWKWebView) {
            let js = "(function(){ try { return window.getSelection().toString(); } catch(e) { return ''; } })();"
            webView.evaluateJavaScript(js) { [weak self] result, _ in
                let text = (result as? String) ?? ""
                DispatchQueue.main.async {
                    self?.onCapturedSelection(text)
                }
            }
        }

        private func jumpToSelection(in webView: LexiconWKWebView) {
            let js = """
            (function(){
              try {
                var sel = window.getSelection();
                if (!sel || sel.rangeCount === 0) return false;
                var node = sel.getRangeAt(0).startContainer;
                var el = node.nodeType === 1 ? node : node.parentElement;
                if (el && el.scrollIntoView) {
                  el.scrollIntoView({block:'nearest', inline:'nearest'});
                  return true;
                }
              } catch(e) {}
              return false;
            })();
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}
#endif

/// AppKit-backed find field: reliably takes first responder (text selected) each time
/// `focusToken` changes, including when it is created in the same update.
struct FindField: NSViewRepresentable {
    var text: String
    var focusToken: Int
    var focusOnAppear: () -> Bool = { false }
    var onChange: (String) -> Void
    var onSubmit: () -> Void
    var onEscape: () -> Void

    func makeNSView(context: Context) -> FocusingSearchField {
        let field = FocusingSearchField()
        field.placeholderString = "Find in article"
        field.sendsSearchStringImmediately = true
        field.delegate = context.coordinator
        field.stringValue = text
        context.coordinator.lastToken = focusToken
        field.wantsFocusOnWindow = focusOnAppear()  // only when ⌘F opened the bar
        return field
    }

    func updateNSView(_ field: FocusingSearchField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        if context.coordinator.lastToken != focusToken {
            context.coordinator.lastToken = focusToken
            _ = focusOnAppear()  // consumed here; don't leak to a later ⌘G-opened bar
            field.requestFocus()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: FindField
        var lastToken = 0
        init(parent: FindField) { self.parent = parent }

        func controlTextDidChange(_ obj: Notification) {
            guard let f = obj.object as? NSTextField else { return }
            parent.onChange(f.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.cancelOperation(_:)):
                parent.onEscape(); return true
            case #selector(NSResponder.insertNewline(_:)):
                parent.onSubmit(); return true
            default:
                return false
            }
        }
    }
}

final class FocusingSearchField: NSSearchField {
    var wantsFocusOnWindow = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsFocusOnWindow, window != nil {
            wantsFocusOnWindow = false
            requestFocus()
        }
    }

    /// Make this field first responder and select its text. Retried on the next
    /// runloop turn because SwiftUI may still be reassigning responders.
    func requestFocus() {
        let apply = { [weak self] in
            guard let self, let window = self.window else { return }
            if self.currentEditor() == nil || window.firstResponder !== self.currentEditor() {
                window.makeFirstResponder(self)
            }
            self.currentEditor()?.selectAll(nil)
        }
        apply()
        DispatchQueue.main.async(execute: apply)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08, execute: apply)
    }
}
