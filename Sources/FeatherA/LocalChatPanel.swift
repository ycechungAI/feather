import AppKit
import WebKit

/// The chat view shown in the browser window's side panel (dockable left/right/bottom via Settings).
/// Embedded in BrowserWindowController's content area instead of a floating popup.
@MainActor
final class LocalChatView: NSView {
    private var pageText = ""
    private var history: [String] = []

    // Header sub-panel
    private let headerView = NSView()
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "Feather AI")
    private let tabControl = NSSegmentedControl()

    // Chat
    private let chatContainer = NSView()
    private let chatScrollView = NSScrollView()
    private let chatTextView = NSTextView()
    private let inputRow = NSView()
    private let inputStack = NSStackView()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private let closeButton = NSButton()

    // Logs
    private let logsContainer = NSView()
    private let logsScrollView = NSScrollView()
    private let logsTextView = NSTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        // Header
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor

        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "brain", accessibilityDescription: "AI") {
            iconView.image = img
        }
        iconView.contentTintColor = NSColor(calibratedRed: 0.1, green: 0.8, blue: 0.8, alpha: 1.0)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .boldSystemFont(ofSize: 12)
        nameLabel.textColor = NSColor.white

        tabControl.translatesAutoresizingMaskIntoConstraints = false
        tabControl.segmentCount = 2
        tabControl.setLabel("Ask", forSegment: 0)
        tabControl.setLabel("Logs", forSegment: 1)
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(tabChanged(_:))

        headerView.addSubview(iconView)
        headerView.addSubview(nameLabel)
        headerView.addSubview(tabControl)

        // Chat
        chatContainer.translatesAutoresizingMaskIntoConstraints = false

        chatScrollView.translatesAutoresizingMaskIntoConstraints = false
        chatScrollView.hasVerticalScroller = true
        chatScrollView.hasHorizontalScroller = false
        chatScrollView.borderType = .bezelBorder
        chatScrollView.documentView = chatTextView
        chatTextView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        chatTextView.autoresizingMask = [.width]
        chatTextView.isEditable = false
        chatTextView.isSelectable = true
        chatTextView.drawsBackground = true
        chatTextView.backgroundColor = NSColor.black
        chatTextView.textColor = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
        chatTextView.font = .systemFont(ofSize: 13)
        chatTextView.isVerticallyResizable = true
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
        inputField.target = self
        inputField.action = #selector(sendChatNow)

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

        chatContainer.addSubview(chatScrollView)
        chatContainer.addSubview(inputRow)
        inputRow.addSubview(inputStack)

        NSLayoutConstraint.activate([
            chatScrollView.topAnchor.constraint(equalTo: chatContainer.topAnchor),
            chatScrollView.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            chatScrollView.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            chatScrollView.bottomAnchor.constraint(equalTo: inputRow.topAnchor),
            inputRow.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
            inputRow.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
            inputRow.bottomAnchor.constraint(equalTo: chatContainer.bottomAnchor),
            inputStack.topAnchor.constraint(equalTo: inputRow.topAnchor),
            inputStack.bottomAnchor.constraint(equalTo: inputRow.bottomAnchor),
            inputStack.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor, constant: 8),
            inputStack.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor, constant: -8),
        ])

        // Logs
        logsContainer.translatesAutoresizingMaskIntoConstraints = false
        logsScrollView.translatesAutoresizingMaskIntoConstraints = false
        logsScrollView.hasVerticalScroller = true
        logsScrollView.borderType = .bezelBorder
        logsScrollView.documentView = logsTextView
        logsTextView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        logsTextView.autoresizingMask = [.width]
        logsTextView.isEditable = false
        logsTextView.isSelectable = true
        logsTextView.drawsBackground = true
        logsTextView.backgroundColor = NSColor.black
        logsTextView.textColor = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
        logsTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logsTextView.isVerticallyResizable = true
        if let container = logsTextView.textContainer {
            container.widthTracksTextView = true
        }
        logsContainer.addSubview(logsScrollView)
        NSLayoutConstraint.activate([
            logsScrollView.topAnchor.constraint(equalTo: logsContainer.topAnchor),
            logsScrollView.leadingAnchor.constraint(equalTo: logsContainer.leadingAnchor),
            logsScrollView.trailingAnchor.constraint(equalTo: logsContainer.trailingAnchor),
            logsScrollView.bottomAnchor.constraint(equalTo: logsContainer.bottomAnchor),
        ])

        // Assemble
        addSubview(headerView)
        addSubview(chatContainer)
        addSubview(logsContainer)
        logsContainer.isHidden = true

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 36),

            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            tabControl.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            tabControl.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

            chatContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            chatContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            chatContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            chatContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            logsContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            logsContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            logsContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            logsContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        inputField.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(pageText: String) {
        self.pageText = pageText
        history = Settings.saveChatHistory ? Self.loadHistory() : []
        inputField.stringValue = ""
        render()
        appendLog("Panel opened. Page text: \(pageText.count) chars.")
    }

    @objc func sendChatNow() {
        let question = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        inputField.stringValue = ""
        history.append("You: \(question)")
        history.append("Feather: Thinking...")
        render()
        Task { @MainActor in
            if let idx = self.history.lastIndex(of: "Feather: Thinking...") { self.history.remove(at: idx) }
            await self.answer(question: question)
            self.render()
        }
    }

    @objc func closeChat() {
        onHide?()
    }

    @objc func tabChanged(_ sender: NSSegmentedControl) {
        let isChat = sender.selectedSegment == 0
        chatContainer.isHidden = !isChat
        logsContainer.isHidden = isChat
    }

    var onHide: (() -> Void)?

    private func render() {
        let turquoise = NSColor(calibratedRed: 0.1, green: 0.8, blue: 0.8, alpha: 1.0)
        let white = NSColor.white
        let attr = NSMutableAttributedString()
        if history.isEmpty {
            attr.append(NSAttributedString(string: "Ask a question about this page.", attributes: [.foregroundColor: NSColor.gray, .font: NSFont.systemFont(ofSize: 13)]))
        } else {
            for (i, entry) in history.enumerated() {
                if i > 0 { attr.append(NSAttributedString(string: "\n\n")) }
                let color: NSColor = entry.hasPrefix("Feather:") ? turquoise : white
                attr.append(NSAttributedString(string: entry, attributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 13)]))
            }
        }
        chatTextView.textStorage?.setAttributedString(attr)
        if Settings.saveChatHistory {
            Self.saveHistory(history)
        }
        let clip = chatScrollView.contentView
        let maxY = max(0, chatTextView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: maxY))
        chatScrollView.reflectScrolledClipView(clip)
    }

    private func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        logsTextView.string += "[\(timestamp)] \(message)\n"
        let clip = logsScrollView.contentView
        let maxY = max(0, logsTextView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: maxY))
        logsScrollView.reflectScrolledClipView(clip)
    }

    private func answer(question: String) async {
        appendLog("Question: \(question)")
        let config = ServicesConfig()
        let router = Router(config: config)
        let result = try? await router.route(question, pageOpen: !pageText.isEmpty)
        guard let result else {
            appendLog("Router returned nil")
            history.append("Feather: The local router didn't answer just now. Start Ollama, then try again.")
            render()
            return
        }
        appendLog("Route: \(result)")
        switch result {
        case .routed(.pageQA), .routed(.nothing):
            let text = (try? await LocalModel(config: config).ask(question: question, pageText: pageText))
                ?? "The local model didn't answer just now. Start Ollama, then try again."
            history.append("Feather: \(text)")
            appendLog("Answer: \(text.prefix(120))")
            render()
        case .routed(.search):
            history.append("Feather: Web search isn't built yet in this build — it comes next, on the basic model.")
            render()
        case .routed(.schedule):
            history.append("Feather: Scheduled tasks aren't built yet in this build.")
            render()
        case .unsure:
            if !pageText.isEmpty {
                let text = (try? await LocalModel(config: config).ask(question: question, pageText: pageText))
                    ?? "The local model didn't answer just now. Start Ollama, then try again."
                history.append("Feather: \(text)")
                appendLog("Answer (unsure fallback): \(text.prefix(120))")
                render()
            } else {
                history.append("Feather: The router wasn't sure which action fits. Try again, or ask a page question.")
                render()
            }
        }
    }

    static var historyURL: URL {
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
}

extension LocalChatView: NSTextFieldDelegate {
    func textFieldShouldReturn(_ field: NSTextField) -> Bool {
        guard field === inputField else { return false }
        sendChatNow()
        return true
    }
}