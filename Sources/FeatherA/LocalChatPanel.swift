import AppKit
import WebKit

/// The chat view shown in the browser window's side panel (dockable left/right/bottom via Settings).
/// Embedded in BrowserWindowController's content area instead of a floating popup.
@MainActor
final class LocalChatView: NSView {
    private var pageText = ""
    private var history: [String] = []

    private let chatScrollView = NSScrollView()
    private let chatTextView = NSTextView()
    private let inputRow = NSView()
    private let inputStack = NSStackView()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        chatScrollView.translatesAutoresizingMaskIntoConstraints = false
        chatScrollView.hasVerticalScroller = true
        chatScrollView.hasHorizontalScroller = false
        chatScrollView.documentView = chatTextView
        chatScrollView.borderType = .bezelBorder

        chatTextView.translatesAutoresizingMaskIntoConstraints = false
        chatTextView.isEditable = false
        chatTextView.isSelectable = true
        chatTextView.drawsBackground = false
        chatTextView.isVerticallyResizable = true
        chatTextView.autoresizingMask = [.width]
        if let container = chatTextView.textContainer {
            container.widthTracksTextView = true
        }

        inputRow.translatesAutoresizingMaskIntoConstraints = false
        inputRow.heightAnchor.constraint(equalToConstant: 44).isActive = true

        inputStack.translatesAutoresizingMaskIntoConstraints = false
        inputStack.orientation = .horizontal
        inputStack.spacing = 6

        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.placeholderString = "Ask about this page"
        inputField.heightAnchor.constraint(equalToConstant: 30).isActive = true

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.title = "Send"
        sendButton.target = self
        sendButton.action = #selector(sendChatNow)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.title = "Close"
        closeButton.target = self
        closeButton.action = #selector(closeChat)

        inputStack.addArrangedSubview(inputField)
        inputStack.addArrangedSubview(sendButton)
        inputStack.addArrangedSubview(closeButton)

        addSubview(chatScrollView)
        addSubview(inputRow)
        inputRow.addSubview(inputStack)

        NSLayoutConstraint.activate([
            chatScrollView.topAnchor.constraint(equalTo: topAnchor),
            chatScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            chatScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            chatScrollView.bottomAnchor.constraint(equalTo: inputRow.topAnchor),
            inputRow.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputRow.bottomAnchor.constraint(equalTo: bottomAnchor),
            inputStack.topAnchor.constraint(equalTo: inputRow.topAnchor),
            inputStack.bottomAnchor.constraint(equalTo: inputRow.bottomAnchor),
            inputStack.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor, constant: 8),
            inputStack.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor, constant: -8),
        ])

        inputField.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(pageText: String) {
        self.pageText = pageText
        history = Settings.saveChatHistory ? Self.loadHistory() : []
        inputField.stringValue = ""
        render()
    }

    @objc func sendChatNow() {
        let question = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        inputField.stringValue = ""
        history.append("You: \(question)")
        history.append("Feather: Thinking...")
        render()
        Task { @MainActor in
            // remove the thinking placeholder then answer
            if let idx = history.lastIndex(of: "Feather: Thinking...") { history.remove(at: idx) }
            await self.answer(question: question)
            self.render()
        }
    }

    @objc func closeChat() {
        onHide?()
    }

    var onHide: (() -> Void)?

    private static var historyURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeatherA", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("chat_history.json")
    }

    static func loadHistory() -> [String] {
        guard let data = try? Data(contentsOf: historyURL),
              let arr = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return arr
    }

    static func saveHistory(_ history: [String]) {
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: historyURL, options: .atomic)
        }
    }

    static func clearHistory() {
        try? FileManager.default.removeItem(at: historyURL)
    }

    private func render() {
        let text = history.isEmpty ? "Ask a question about this page." : history.joined(separator: "\n\n")
        chatTextView.string = text
        chatTextView.sizeToFit()
        if Settings.saveChatHistory {
            Self.saveHistory(history)
        }
        // scroll to bottom
        let clip = chatScrollView.contentView
        let maxY = max(0, chatTextView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: maxY))
        chatScrollView.reflectScrolledClipView(clip)
    }

    private func answer(question: String) async {
        let config = ServicesConfig()
        let router = Router(config: config)
        let result = try? await router.route(question, pageOpen: !pageText.isEmpty)
        guard let result else {
            history.append("Feather: The local router didn't answer just now. Start Ollama, then try again.")
            render()
            return
        }
        switch result {
        case .routed(.pageQA), .routed(.nothing):
            let text = (try? await LocalModel(config: config).ask(question: question, pageText: pageText))
                ?? "The local model didn't answer just now. Start Ollama, then try again."
            history.append("Feather: \(text)")
            render()
        case .routed(.search):
            history.append("Feather: Web search isn't built yet in this build — it comes next, on the basic model.")
            render()
        case .routed(.schedule):
            history.append("Feather: Scheduled tasks aren't built yet in this build.")
            render()
        case .unsure:
            history.append("Feather: The router wasn't sure which action fits. Try again, or ask a page question.")
            render()
        }
    }
}

extension LocalChatView: NSTextFieldDelegate {
    func textFieldShouldReturn(_ field: NSTextField) -> Bool {
        guard field === inputField else { return false }
        sendChatNow()
        return true
    }
}