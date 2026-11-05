import AppKit
import WebKit

/// The "Ask Local Model" panel: the request is routed by the small decision model, then answered by
/// the answer model. Local only; see docs/AGENTIC.md. Lives in a chat side panel, not a popup.
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

    private static func askQuestion(pageText: String, window: NSWindow) {
        if let controller = BrowserWindowController.all.first(where: { $0.window === window }) {
            controller.showAskPanel(pageText: pageText)
        }
    }

    private static func route(question: String, pageText: String, window: NSWindow) async {
        let router = Router(config: .load())
        switch try? await router.route(question, pageOpen: !pageText.isEmpty) {
        case .routed(.pageQA), .routed(.nothing):
            await LocalModelPrompt.answer(question: question, pageText: pageText, window: window)
        case .routed(.search):
            show("Search isn't built yet. It comes next, on the basic model.", title: question, window: window)
        case .routed(.schedule):
            show("Scheduled tasks aren't built yet. They come after search.", title: question, window: window)
        case .unsure:
            chooseRoute(question: question, pageText: pageText, window: window)
        case nil:
            await LocalModelPrompt.answer(question: question, pageText: pageText, window: window)
        }
    }

    private static func chooseRoute(question: String, pageText: String, window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "The router isn't sure"
        alert.informativeText = "Pick what to do with this."
        alert.addButton(withTitle: "Answer from this page")
        alert.addButton(withTitle: "Search the web")
        alert.addButton(withTitle: "Schedule a task")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn {
                Task { @MainActor in await answer(question: question, pageText: pageText, window: window) }
            } else if response == .alertSecondButtonReturn {
                show("Search isn't built yet. It comes next, on the basic model.", title: question, window: window)
            } else if response == .alertThirdButtonReturn {
                show("Scheduled tasks aren't built yet. They come after search.", title: question, window: window)
            }
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

    private static func showNotRunning(window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Ollama isn't running"
        alert.informativeText = "FeatherA answers with Ollama on this Mac. Install Ollama from ollama.com, start it, then try again. FeatherA doesn't install or start Ollama for you."
        alert.addButton(withTitle: "Open ollama.com")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn, let url = URL(string: "https://ollama.com/download") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private static func offerDownload(name: String, model: LocalModel, pageText: String, window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Download \(name)?"
        alert.informativeText = "FeatherA needs this small model to answer. Ollama downloads it from its library and it then runs on this Mac."
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
