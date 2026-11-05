import AppKit
import WebKit

/// The local model's chat side panel. Opens docked to the side of the browser window as a chat
/// window with a history and an input field, instead of the old alert popup. Opened by the toolbar's
/// Ask AI button via LocalModelPrompt.ask; answers are routed by the small router and run on Ollama.
@MainActor
final class LocalChatPanel: NSPanel {
    static let shared = LocalChatPanel()

    private weak var ownerWindow: NSWindow?
    private var pageText = ""
    private var history: [String] = []

    private let chatScrollView = NSScrollView()
    private let chatTextView = NSTextView()
    private let chatContainer = NSView()
    private let inputRow = NSView()
    private let inputStack = NSStackView()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private let closeButton = NSButton()

    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: true)
        level = .modalPanel
        isMovableByWindowBackground = true
        titlebarAppearsTransparent = true
        titleVisibility = .hidden
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .windowBackgroundColor

        chatScrollView.translatesAutoresizingMaskIntoConstraints = false
        chatScrollView.hasVerticalScroller = true
        chatScrollView.hasHorizontalScroller = false
        chatScrollView.documentView = chatTextView

        chatTextView.translatesAutoresizingMaskIntoConstraints = false
        chatTextView.isEditable = false
        chatTextView.isSelectable = true
        chatTextView.drawsBackground = false

        inputRow.translatesAutoresizingMaskIntoConstraints = false
        inputRow.heightAnchor.constraint(equalToConstant: 44).isActive = true
        inputStack.translatesAutoresizingMaskIntoConstraints = false
        inputStack.orientation = .horizontal
        inputStack.spacing = 6
        inputStack.addArrangedSubview(inputField)
        inputStack.addArrangedSubview(sendButton)
        inputStack.addArrangedSubview(closeButton)

        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.placeholderString = "Ask about this page"
        inputField.heightAnchor.constraint(equalToConstant: 30).isActive = true
        inputField.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true

        sendButton.translatesAutoresizingMaskIntoConstraints = false
        sendButton.title = "Send"
        sendButton.target = self
        sendButton.action = #selector(sendChatNow)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.title = "Close"
        closeButton.target = self
        closeButton.action = #selector(closeChat)

        chatContainer.translatesAutoresizingMaskIntoConstraints = false
        contentView = chatContainer
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
            inputStack.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor),
            inputStack.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor),
        ])

        inputField.delegate = self
    }

    func show(pageText: String, owner: NSWindow) {
        ownerWindow = owner
        self.pageText = pageText
        history = []
        inputField.stringValue = ""
        title = "Ask AI"
        let frame = owner.frame
        let height = min(max(frame.height * 0.75, 320), 520)
        var panelFrame = frame
        panelFrame.size.height = height
        switch Settings.askPanelPosition {
        case "left":
            panelFrame.origin.x = frame.minX - panelFrame.width - 12
            panelFrame.origin.y = frame.minY + (frame.height - height) / 2
        case "bottom":
            panelFrame.origin.y = frame.maxY + 8
            panelFrame.size.height = min(max(frame.height * 0.5, 280), 420)
        default:
            panelFrame.origin.x = frame.maxX + 12
            panelFrame.origin.y = frame.minY + (frame.height - height) / 2 - 20
        }
        setFrame(panelFrame, display: true)
        orderFrontRegardless()
        makeKeyAndOrderFront(nil)
        render()
    }

    @objc func sendChatNow() {
        let question = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        inputField.stringValue = ""
        history.append("You: \(question)")
        render()
        Task { @MainActor in
            await self.answer(question: question)
        }
    }

    @objc func closeChat() {
        orderOut(nil)
    }

    private func render() {
        let text = history.isEmpty ? "Ask a question about this page." : history.joined(separator: "\n\n")
        chatTextView.string = text
        chatTextView.sizeToFit()
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

extension LocalChatPanel: NSTextFieldDelegate {
    func textFieldShouldReturn(_ field: NSTextField) -> Bool {
        guard field === inputField else { return false }
        sendChatNow()
        return true
    }
}
