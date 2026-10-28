import SwiftUI
import WebKit

@MainActor
final class RichTextEditorBridge {
    var perform: ((String, String?) -> Void)?
}

struct RichTextEditor: UIViewRepresentable {
    let noteID: String
    let content: String
    let bridge: RichTextEditorBridge
    let onChange: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "noteChanged")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isAccessibilityElement = true
        webView.accessibilityLabel = "笔记正文编辑器"
        webView.accessibilityIdentifier = "note-body-editor"
        context.coordinator.webView = webView
        context.coordinator.pendingHTML = DiaryText.contentWithoutMetadata(in: content)
        bridge.perform = { [weak coordinator = context.coordinator] command, value in
            coordinator?.execute(command, value: value)
        }
        webView.loadHTMLString(Self.document, baseURL: nil)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        let renderedContent = DiaryText.contentWithoutMetadata(in: content)
        if context.coordinator.noteID != noteID {
            context.coordinator.noteID = noteID
            context.coordinator.setHTML(renderedContent)
        } else if !context.coordinator.isDocumentReady {
            // Keep the newest remotely loaded content until the initial page
            // finishes. Afterwards the contenteditable DOM owns the selection;
            // writing the same SwiftUI state back would move the caret.
            context.coordinator.pendingHTML = renderedContent
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "noteChanged")
        coordinator.bridge.perform = nil
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var parent: RichTextEditor
        weak var webView: WKWebView?
        var noteID: String
        var pendingHTML: String
        var currentHTML = ""
        var isEditing = false
        var isDocumentReady = false

        init(_ parent: RichTextEditor) {
            self.parent = parent
            self.noteID = parent.noteID
            self.pendingHTML = DiaryText.contentWithoutMetadata(in: parent.content)
        }

        var bridge: RichTextEditorBridge { parent.bridge }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isDocumentReady = true
            setHTML(pendingHTML)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let html = body["content"] as? String else { return }
            currentHTML = html
            pendingHTML = html
            parent.onChange(html)
        }

        func setHTML(_ html: String) {
            let renderedContent = DiaryText.contentWithoutMetadata(in: html)
            pendingHTML = renderedContent
            currentHTML = renderedContent
            guard let data = try? JSONSerialization.data(withJSONObject: [renderedContent]),
                  let array = String(data: data, encoding: .utf8) else { return }
            let literal = String(array.dropFirst().dropLast())
            webView?.evaluateJavaScript("window.synoSetContent(\(literal));")
        }

        func execute(_ command: String, value: String?) {
            func literal(_ value: Any) -> String {
                guard let data = try? JSONSerialization.data(withJSONObject: [value]), let array = String(data: data, encoding: .utf8) else { return "null" }
                return String(array.dropFirst().dropLast())
            }
            isEditing = true
            webView?.evaluateJavaScript("window.synoCommand(\(literal(command)), \(literal(value as Any)));") { [weak self] _, _ in
                Task { @MainActor in self?.isEditing = false }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else { decisionHandler(.allow) }
        }
    }

    private static let document = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
    <style>
    :root { color-scheme: light dark; --paper:#fff; --ink:#262628; --muted:#8b8b90; --accent:#407a63; --rule:#e7e7e9; }
    @media (prefers-color-scheme:dark) { :root { --paper:#1c1c1e; --ink:#f2f2f2; --muted:#929298; --rule:#38383a; } }
    * { box-sizing:border-box; -webkit-tap-highlight-color:transparent; }
    html,body { margin:0; padding:0; background:var(--paper); }
    body { font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif; color:var(--ink); font-size:17px; line-height:1.72; overflow-wrap:break-word; }
    #editor { min-height:85vh; padding:12px 24px 140px; outline:none; max-width:820px; margin:0 auto; caret-color:var(--accent); }
    @media(max-width:500px) { #editor { padding:8px 20px 120px; } }
    p { margin:0 0 1em; } h1,h2,h3 { line-height:1.32; margin:1.35em 0 .55em; font-weight:700; }
    h1 { font-size:2em; } h2 { font-size:1.55em; } h3 { font-size:1.2em; }
    ul,ol { padding-left:1.55em; margin:.5em 0 1em; } li { margin:.28em 0; padding-left:.12em; }
    blockquote { margin:1.25em 0; padding:.15em 0 .15em 1em; border-left:3px solid var(--accent); color:var(--muted); }
    code { font-family:ui-monospace,SFMono-Regular,Menlo,monospace; font-size:.88em; background:var(--rule); padding:.16em .38em; border-radius:5px; }
    pre { white-space:pre-wrap; background:var(--rule); padding:16px; border-radius:10px; line-height:1.55; }
    pre code { padding:0; background:none; } a { color:var(--accent); text-decoration:none; }
    img,video { max-width:100%; height:auto; border-radius:8px; } hr { border:0; border-top:1px solid var(--rule); margin:2em 0; }
    .task { display:flex; gap:.65em; align-items:flex-start; margin:.45em 0; }
    .task-box { flex:0 0 auto; color:var(--accent); font-size:1.15em; line-height:1.65; cursor:pointer; user-select:none; }
    .task.done .task-text { opacity:.5; text-decoration:line-through; }
    #editor:empty:before, #editor.is-empty:before { content:"写下你的今天…"; color:var(--muted); pointer-events:none; }
    </style></head><body><div id="editor" contenteditable="true" autocapitalize="sentences"></div>
    <script>
    const editor = document.getElementById('editor');
    function updateEmpty() { editor.classList.toggle('is-empty', !editor.textContent.trim() && !editor.querySelector('img,video')); }
    function notify() { updateEmpty(); window.webkit.messageHandlers.noteChanged.postMessage({content:editor.innerHTML}); }
    editor.addEventListener('input',notify);
    editor.addEventListener('keyup',()=>{});
    editor.addEventListener('click',e=>{ if(e.target.classList.contains('task-box')) { const task=e.target.parentElement; task.classList.toggle('done'); e.target.textContent=task.classList.contains('done')?'☑':'☐'; notify(); } });
    window.synoSetContent = function(html) { editor.innerHTML=html||'<p><br></p>'; updateEmpty(); };
    window.synoCommand = function(command,value) {
      editor.focus();
      const selection=window.getSelection();
      if(!selection.rangeCount||!editor.contains(selection.anchorNode)) {
        const range=document.createRange();
        range.selectNodeContents(editor); range.collapse(false);
        selection.removeAllRanges(); selection.addRange(range);
      }
      if(command==='h2'||command==='h3') document.execCommand('formatBlock',false,'<'+command+'>');
      else if(command==='paragraph') document.execCommand('formatBlock',false,'<p>');
      else if(command==='code') document.execCommand('formatBlock',false,'<pre>');
      else if(command==='task') document.execCommand('insertHTML',false,'<div class="task"><span class="task-box" contenteditable="false">☐</span><div class="task-text">待办事项</div></div><p><br></p>');
      else document.execCommand(command,false,value);
      notify();
    };
    </script></body></html>
    """
}
