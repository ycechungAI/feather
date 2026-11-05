import AppKit
import WebKit

/// The "Ask Local Model" sheet: a question box, then the answer in a scrollable sheet.
@MainActor
enum LocalModelPrompt {
    static func ask(webView: WKWebView, window: NSWindow) {
        webView.evaluateJavaScript("document.body ? document.body.innerText : ''") { result, _ in
            let pageText = result as? String ?? ""
            Task { @MainActor in await checkThenAsk(pageText: pageText, window: window) }
        }
    }

    private static func checkThenAsk(pageText: String, window: NSWindow) async {
        let model = LocalModel(config: .load())
        guard await model.isRunning() else {
            showNotRunning(window: window)
            return
        }
        let answerModel = model.config.answerModel
        guard await model.modelInstalled(answerModel) else {
            offerDownload(name: answerModel, model: model, pageText: pageText, window: window)
            return
        }
        askQuestion(pageText: pageText, window: window)
    }

    private static func offerDownload(name: String, model: LocalModel, pageText: String, window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Download \(name)?"
        alert.informativeText = "Feather needs this small model to answer. Ollama downloads it from its library and it then runs on this Mac."
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in
                do {
                    try await model.pull(name)
                    askQuestion(pageText: pageText, window: window)
                } catch {
                    show((error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                         title: "The download didn't finish", window: window)
                }
            }
        }
    }

    private static func showNotRunning(window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Ollama isn't running"
        alert.informativeText = "Feather answers with Ollama on this Mac. Install Ollama from ollama.com, start it, then try again. Feather doesn't install or start Ollama for you."
        alert.addButton(withTitle: "Open ollama.com")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn, let url = URL(string: "https://ollama.com/download") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private static func askQuestion(pageText: String, window: NSWindow) {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24))
        field.placeholderString = "Ask about this page"
        let alert = NSAlert()
        alert.messageText = "Ask the local model"
        alert.informativeText = "Runs on this Mac with Ollama. The page text doesn't leave it."
        alert.accessoryView = field
        alert.addButton(withTitle: "Ask")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            let question = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard response == .alertFirstButtonReturn, !question.isEmpty else { return }
            Task { @MainActor in await answer(question: question, pageText: pageText, window: window) }
        }
    }

    private static func answer(question: String, pageText: String, window: NSWindow) async {
        let model = LocalModel(config: .load())
        let text: String
        do {
            text = try await model.ask(question: question, pageText: pageText)
        } catch {
            text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        show(text, title: question, window: window)
    }

    private static func show(_ text: String, title: String, window: NSWindow) {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        textView.string = text
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 13)
        textView.isVerticallyResizable = true
        textView.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 240))
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder

        let alert = NSAlert()
        alert.messageText = title
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Done")
        alert.beginSheetModal(for: window, completionHandler: { _ in })
    }
}
