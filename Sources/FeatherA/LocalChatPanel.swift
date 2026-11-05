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
    private let nameLabel = NSTextField(labelWithString: "AI")
    private let tabControl = NSSegmentedControl()

    // Chat
    private let chatContainer = NSView()
    private let logsContainer = NSView()
    private let tasksContainer = NSView()
    private let tasksScrollView = NSScrollView()
    private let tasksTextView = NSTextView()
    private let taskRowsStack = NSStackView()
    private let tasksContentStack = NSStackView()
    private let resultsContainer = NSView()
    private let resultsScrollView = NSScrollView()
    private let resultsTextView = NSTextView()
    private let taskPicker = NSPopUpButton()
    private let runPicker = NSPopUpButton()
    private var currentResultTaskId: String?
    private var currentRuns: [[String: Any]] = []
    var pendingEditFilename: String?
    var pendingEditTextView: NSTextView?
    var pendingEditSaveButton: NSButton?
    private var currentTasksForResults: [[String: Any]] = []
    private var logsMode: Bool = false
    private let taskButtonBar = NSStackView()
    private let taskBottomBar = NSStackView()
    private let taskFilterPicker = NSPopUpButton()
    private var taskButtons: [NSButton] = []
    private var currentTasks: [[String: Any]] = []
    private let chatScrollView = NSScrollView()
    private let chatTextView = NSTextView()
    private let inputRow = NSView()
    private let inputStack = NSStackView()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private let closeButton = NSButton()

    // Resize handle
    private let resizeHandle = NSView()
    private var panStartSize: CGFloat = 0
    private var panStartLocation: CGFloat = 0
    var panelPosition: String = "right"
    private var handleConstraints: [NSLayoutConstraint] = []
    private var lastButtonWidth: CGFloat = 0
    private let logsScrollView = NSScrollView()
    private let logsTextView = NSTextView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 1).cgColor

        // Header
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor(white: 0.2, alpha: 1).cgColor

        iconView.translatesAutoresizingMaskIntoConstraints = false
        if let img = NSImage(systemSymbolName: "brain", accessibilityDescription: "AI") {
            iconView.image = img
        }
        iconView.contentTintColor = NSColor(calibratedRed: 0.1, green: 0.8, blue: 0.8, alpha: 1.0)

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = .boldSystemFont(ofSize: 12)
        nameLabel.textColor = NSColor.white

        tabControl.translatesAutoresizingMaskIntoConstraints = false
        tabControl.segmentCount = 4
        tabControl.setLabel("Ask", forSegment: 0)
        tabControl.setLabel("Tasks", forSegment: 1)
        tabControl.setLabel("Results", forSegment: 2)
        tabControl.setLabel(">>", forSegment: 3)
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(tabChanged(_:))
        tabControl.segmentStyle = .texturedSquare
        tabControl.appearance = NSAppearance(named: .darkAqua)

        headerView.addSubview(iconView)
        headerView.addSubview(nameLabel)
        headerView.addSubview(tabControl)

        // Chat
        chatContainer.translatesAutoresizingMaskIntoConstraints = false

        chatScrollView.translatesAutoresizingMaskIntoConstraints = false
        chatScrollView.hasVerticalScroller = false
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

        let chatUp = NSButton(title: "<", target: self, action: #selector(scrollChatUp(_:)))
        let chatDown = NSButton(title: ">", target: self, action: #selector(scrollChatDown(_:)))
        chatUp.bezelStyle = .recessed; chatUp.controlSize = .mini
        chatDown.bezelStyle = .recessed; chatDown.controlSize = .mini
        inputStack.addArrangedSubview(chatUp)
        inputStack.addArrangedSubview(chatDown)
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
        logsScrollView.hasVerticalScroller = false
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
        let logsNav = NSStackView()
        logsNav.translatesAutoresizingMaskIntoConstraints = false
        logsNav.orientation = .horizontal
        logsNav.spacing = 4
        let logsUp = NSButton(title: "<", target: self, action: #selector(scrollLogsUp(_:)))
        let logsDown = NSButton(title: ">", target: self, action: #selector(scrollLogsDown(_:)))
        logsUp.bezelStyle = .recessed; logsUp.controlSize = .mini
        logsDown.bezelStyle = .recessed; logsDown.controlSize = .mini
        logsNav.addArrangedSubview(logsUp)
        logsNav.addArrangedSubview(logsDown)
        logsContainer.addSubview(logsScrollView)
        logsContainer.addSubview(logsNav)
        NSLayoutConstraint.activate([
            logsScrollView.topAnchor.constraint(equalTo: logsContainer.topAnchor),
            logsScrollView.leadingAnchor.constraint(equalTo: logsContainer.leadingAnchor),
            logsScrollView.trailingAnchor.constraint(equalTo: logsContainer.trailingAnchor),
            logsScrollView.bottomAnchor.constraint(equalTo: logsNav.topAnchor, constant: -4),
            logsNav.leadingAnchor.constraint(equalTo: logsContainer.leadingAnchor, constant: 8),
            logsNav.bottomAnchor.constraint(equalTo: logsContainer.bottomAnchor, constant: -4),
            logsNav.heightAnchor.constraint(equalToConstant: 20),
        ])

        // Tasks
        tasksContainer.translatesAutoresizingMaskIntoConstraints = false
        tasksContainer.appearance = NSAppearance(named: .darkAqua)
        tasksScrollView.translatesAutoresizingMaskIntoConstraints = false
        tasksScrollView.hasVerticalScroller = false
        tasksScrollView.borderType = .bezelBorder
        tasksContentStack.addArrangedSubview(taskRowsStack)
        tasksContentStack.addArrangedSubview(tasksTextView)
        tasksScrollView.documentView = tasksContentStack
        tasksTextView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        tasksTextView.autoresizingMask = [.width]
        tasksTextView.isEditable = false
        tasksTextView.isSelectable = true
        tasksTextView.drawsBackground = true
        tasksTextView.backgroundColor = NSColor.black
        tasksTextView.textColor = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
        tasksTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        tasksTextView.isVerticallyResizable = true
        if let container = tasksTextView.textContainer {
            container.widthTracksTextView = true
        }
        tasksContainer.addSubview(tasksScrollView)
        tasksContainer.addSubview(taskButtonBar)
        tasksContainer.addSubview(taskBottomBar)
        tasksContainer.addSubview(taskFilterPicker)
        taskButtonBar.translatesAutoresizingMaskIntoConstraints = false
        taskButtonBar.orientation = .vertical
        taskButtonBar.spacing = 4
        taskButtonBar.alignment = .leading
        taskRowsStack.translatesAutoresizingMaskIntoConstraints = false
        taskRowsStack.orientation = .vertical
        taskRowsStack.spacing = 2
        taskRowsStack.alignment = .leading
        tasksContentStack.translatesAutoresizingMaskIntoConstraints = false
        tasksContentStack.orientation = .vertical
        tasksContentStack.spacing = 0
        tasksContentStack.alignment = .leading
        taskBottomBar.translatesAutoresizingMaskIntoConstraints = false
        taskBottomBar.orientation = .horizontal
        taskBottomBar.spacing = 6
        taskBottomBar.alignment = .centerY
        taskFilterPicker.translatesAutoresizingMaskIntoConstraints = false
        taskFilterPicker.target = self
        taskFilterPicker.action = #selector(taskFilterChanged(_:))
        taskFilterPicker.font = .systemFont(ofSize: 10)
        taskFilterPicker.appearance = NSAppearance(named: .darkAqua)
        taskFilterPicker.menu?.appearance = NSAppearance(named: .darkAqua)
        // buttons created in setupTaskButtons() called from configure
        NSLayoutConstraint.activate([
            taskFilterPicker.topAnchor.constraint(equalTo: tasksContainer.topAnchor, constant: 0),
            taskFilterPicker.leadingAnchor.constraint(equalTo: tasksContainer.leadingAnchor, constant: 8),
            taskFilterPicker.widthAnchor.constraint(equalTo: tasksContainer.widthAnchor, multiplier: 0.5, constant: -12),
            taskFilterPicker.heightAnchor.constraint(equalToConstant: 22),
            taskButtonBar.topAnchor.constraint(equalTo: taskFilterPicker.bottomAnchor, constant: 2),
            taskButtonBar.leadingAnchor.constraint(equalTo: tasksContainer.leadingAnchor, constant: 8),
            taskButtonBar.trailingAnchor.constraint(equalTo: tasksContainer.trailingAnchor, constant: -8),
            tasksScrollView.topAnchor.constraint(equalTo: taskButtonBar.bottomAnchor, constant: 2),
            tasksScrollView.leadingAnchor.constraint(equalTo: tasksContainer.leadingAnchor),
            tasksScrollView.trailingAnchor.constraint(equalTo: tasksContainer.trailingAnchor),
            tasksScrollView.bottomAnchor.constraint(equalTo: taskBottomBar.topAnchor, constant: -2),
            tasksContentStack.widthAnchor.constraint(equalTo: tasksScrollView.widthAnchor),
            taskBottomBar.leadingAnchor.constraint(equalTo: tasksContainer.leadingAnchor, constant: 8),
            taskBottomBar.trailingAnchor.constraint(equalTo: tasksContainer.trailingAnchor, constant: -8),
            taskBottomBar.bottomAnchor.constraint(equalTo: tasksContainer.bottomAnchor, constant: -2),
            taskBottomBar.heightAnchor.constraint(equalToConstant: 24),
        ])

        // Results
        resultsContainer.translatesAutoresizingMaskIntoConstraints = false
        resultsContainer.wantsLayer = true
        resultsContainer.layer?.backgroundColor = NSColor(white: 0.05, alpha: 1).cgColor
        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
        resultsScrollView.hasVerticalScroller = false
        resultsScrollView.borderType = .bezelBorder
        resultsScrollView.documentView = resultsTextView
        resultsTextView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        resultsTextView.autoresizingMask = [.width]
        resultsTextView.isEditable = false
        resultsTextView.isSelectable = true
        resultsTextView.drawsBackground = true
        resultsTextView.backgroundColor = NSColor.black
        resultsTextView.textColor = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
        resultsTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        resultsTextView.isVerticallyResizable = true
        if let container = resultsTextView.textContainer {
            container.widthTracksTextView = true
        }
        resultsTextView.string = ""
        taskPicker.translatesAutoresizingMaskIntoConstraints = false
        taskPicker.target = self
        taskPicker.action = #selector(taskPicked(_:))
        taskPicker.font = .systemFont(ofSize: 10)
        taskPicker.appearance = NSAppearance(named: .darkAqua)
        taskPicker.menu?.appearance = NSAppearance(named: .darkAqua)
        runPicker.translatesAutoresizingMaskIntoConstraints = false
        runPicker.target = self
        runPicker.action = #selector(runPicked(_:))
        runPicker.font = .systemFont(ofSize: 10)
        runPicker.appearance = NSAppearance(named: .darkAqua)
        runPicker.menu?.appearance = NSAppearance(named: .darkAqua)
        let resultsNav = NSStackView()
        resultsNav.translatesAutoresizingMaskIntoConstraints = false
        resultsNav.orientation = .horizontal
        resultsNav.spacing = 4
        let resultsUp = NSButton(title: "<", target: self, action: #selector(scrollResultsUp(_:)))
        let resultsDown = NSButton(title: ">", target: self, action: #selector(scrollResultsDown(_:)))
        resultsUp.bezelStyle = .recessed; resultsUp.controlSize = .mini
        resultsDown.bezelStyle = .recessed; resultsDown.controlSize = .mini
        resultsNav.addArrangedSubview(resultsUp)
        resultsNav.addArrangedSubview(resultsDown)
        resultsContainer.addSubview(taskPicker)
        resultsContainer.addSubview(runPicker)
        resultsContainer.addSubview(resultsScrollView)
        resultsContainer.addSubview(resultsNav)
        NSLayoutConstraint.activate([
            taskPicker.topAnchor.constraint(equalTo: resultsContainer.topAnchor, constant: 4),
            taskPicker.leadingAnchor.constraint(equalTo: resultsContainer.leadingAnchor, constant: 8),
            taskPicker.widthAnchor.constraint(equalTo: resultsContainer.widthAnchor, multiplier: 0.4, constant: -12),
            taskPicker.heightAnchor.constraint(equalToConstant: 24),
            runPicker.topAnchor.constraint(equalTo: resultsContainer.topAnchor, constant: 4),
            runPicker.leadingAnchor.constraint(equalTo: taskPicker.trailingAnchor, constant: 8),
            runPicker.trailingAnchor.constraint(equalTo: resultsContainer.trailingAnchor, constant: -8),
            runPicker.heightAnchor.constraint(equalToConstant: 24),
            resultsScrollView.topAnchor.constraint(equalTo: taskPicker.bottomAnchor, constant: 4),
            resultsScrollView.leadingAnchor.constraint(equalTo: resultsContainer.leadingAnchor),
            resultsScrollView.trailingAnchor.constraint(equalTo: resultsContainer.trailingAnchor),
            resultsScrollView.bottomAnchor.constraint(equalTo: resultsNav.topAnchor, constant: -4),
            resultsScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120),
            resultsNav.leadingAnchor.constraint(equalTo: resultsContainer.leadingAnchor, constant: 8),
            resultsNav.bottomAnchor.constraint(equalTo: resultsContainer.bottomAnchor, constant: -4),
            resultsNav.heightAnchor.constraint(equalToConstant: 20),
        ])

        // Assemble
        addSubview(headerView)
        addSubview(chatContainer)
        addSubview(logsContainer)
        addSubview(tasksContainer)
        addSubview(resultsContainer)
        logsContainer.isHidden = true
        tasksContainer.isHidden = true
        resultsContainer.isHidden = true

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 20),

            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 2),
            nameLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: tabControl.leadingAnchor, constant: -4),

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

            tasksContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tasksContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            tasksContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            tasksContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            resultsContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            resultsContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            resultsContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            resultsContainer.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // Resize handle
        resizeHandle.translatesAutoresizingMaskIntoConstraints = false
        resizeHandle.wantsLayer = true
        resizeHandle.layer?.backgroundColor = NSColor(white: 0.3, alpha: 1).cgColor
        addSubview(resizeHandle)
        let pan = NSPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        resizeHandle.addGestureRecognizer(pan)

        inputField.delegate = self
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(pageText: String, position: String = "right") {
        self.pageText = pageText
        self.panelPosition = position
        history = Settings.saveChatHistory ? Self.loadHistory() : []
        inputField.stringValue = ""
        render()
        appendLog("Panel opened. Page text: \(pageText.count) chars.")
        setupHandle()
        setupTaskButtons()
    }

    private func setupHandle() {
        NSLayoutConstraint.deactivate(handleConstraints)
        handleConstraints.removeAll()
        switch panelPosition {
        case "left":
            resizeHandle.isHidden = false
            handleConstraints = [
                resizeHandle.topAnchor.constraint(equalTo: topAnchor),
                resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
                resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
                resizeHandle.widthAnchor.constraint(equalToConstant: 6),
            ]
        case "bottom":
            resizeHandle.isHidden = true
            handleConstraints = []
        default:
            resizeHandle.isHidden = false
            handleConstraints = [
                resizeHandle.topAnchor.constraint(equalTo: topAnchor),
                resizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
                resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
                resizeHandle.widthAnchor.constraint(equalToConstant: 6),
            ]
        }
        NSLayoutConstraint.activate(handleConstraints)
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

    @objc func handlePan(_ gesture: NSPanGestureRecognizer) {
        let loc = gesture.location(in: self)
        switch gesture.state {
        case .began:
            if panelPosition == "bottom" {
                panStartSize = self.frame.height
                panStartLocation = loc.y
            } else {
                panStartSize = self.frame.width
                panStartLocation = loc.x
            }
        case .changed:
            let delta: CGFloat
            if panelPosition == "bottom" {
                delta = loc.y - panStartLocation
            } else if panelPosition == "left" {
                delta = loc.x - panStartLocation
            } else {
                delta = panStartLocation - loc.x
            }
            let newSize = max(200, panStartSize + delta)
            onResize?(newSize)
        default:
            break
        }
    }

    @objc func tabChanged(_ sender: NSSegmentedControl) {
        if !logsMode {
            // normal mode
            if sender.selectedSegment == 3 {
                // toggle to logs mode
                logsMode = true
                tabControl.segmentCount = 2
                tabControl.setLabel("<<", forSegment: 0)
                tabControl.setLabel("Logs", forSegment: 1)
                tabControl.selectedSegment = 1
                chatContainer.isHidden = true
                tasksContainer.isHidden = true
                resultsContainer.isHidden = true
                logsContainer.isHidden = false
                return
            }
            chatContainer.isHidden = sender.selectedSegment != 0
            tasksContainer.isHidden = sender.selectedSegment != 1
            resultsContainer.isHidden = sender.selectedSegment != 2
            logsContainer.isHidden = true
            if sender.selectedSegment == 1 {
                fetchTasks()
            }
            if sender.selectedSegment == 2 {
                fetchResultsTasks()
            }
        } else {
            if sender.selectedSegment == 0 {
                // toggle back
                logsMode = false
                tabControl.segmentCount = 4
                tabControl.setLabel("Ask", forSegment: 0)
                tabControl.setLabel("Tasks", forSegment: 1)
                tabControl.setLabel("Results", forSegment: 2)
                tabControl.setLabel(">>", forSegment: 3)
                tabControl.selectedSegment = 0
                chatContainer.isHidden = false
                tasksContainer.isHidden = true
                resultsContainer.isHidden = true
                logsContainer.isHidden = true
                return
            }
            // Logs tab selected
            chatContainer.isHidden = true
            tasksContainer.isHidden = true
            resultsContainer.isHidden = true
            logsContainer.isHidden = false
        }
    }

    var onHide: (() -> Void)?
    var onResize: ((CGFloat) -> Void)?

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

    private func buildTaskRows(tasks: [[String: Any]]) {
        for v in taskRowsStack.arrangedSubviews { taskRowsStack.removeArrangedSubview(v); v.removeFromSuperview() }
        let twoColumns = (panelPosition == "bottom")
        let makeRow: (Int, [String: Any]) -> NSStackView = { i, t in
            let name = t["name"] as? String ?? "?"
            let enabled = t["enabled"] as? Bool ?? false
            let sched = t["schedule"] as? String ?? "?"
            let status = t["status"] as? String ?? "?"
            let next = t["next_run"] as? String ?? "?"
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6
            row.alignment = .centerY
            let label = NSTextField(labelWithString: String(format: "%2d  %@ %@   %@ · %@ · %@", i+1, enabled ? "●" : "○", name, sched, status, next))
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            label.textColor = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
            label.lineBreakMode = .byTruncatingTail
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let editBtn = NSButton(title: "Edit", target: self, action: #selector(self.editTaskByIndex(_:)))
            editBtn.bezelStyle = .recessed
            editBtn.controlSize = .mini
            editBtn.tag = i
            editBtn.setContentHuggingPriority(.required, for: .horizontal)
            let runBtn = NSButton(title: "Run", target: self, action: #selector(self.runTaskByIndex(_:)))
            runBtn.bezelStyle = .recessed
            runBtn.controlSize = .mini
            runBtn.tag = i
            runBtn.setContentHuggingPriority(.required, for: .horizontal)
            let spacer = NSView()
            spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            row.addArrangedSubview(label)
            row.addArrangedSubview(spacer)
            row.addArrangedSubview(editBtn)
            row.addArrangedSubview(runBtn)
            return row
        }
        if twoColumns {
            let width = self.bounds.width > 0 ? self.bounds.width : 1280
            let ncols = width >= 900 ? 3 : (width >= 500 ? 2 : 1)
            var cols: [NSStackView] = (0..<ncols).map { _ in
                let st = NSStackView()
                st.orientation = .vertical
                st.spacing = 2
                st.alignment = .leading
                return st
            }
            for (i, t) in tasks.enumerated() {
                cols[i % ncols].addArrangedSubview(makeRow(i, t))
            }
            let container = NSStackView(views: cols)
            container.orientation = .horizontal
            container.spacing = 8
            container.alignment = .top
            taskRowsStack.addArrangedSubview(container)
        } else {
            for (i, t) in tasks.enumerated() {
                taskRowsStack.addArrangedSubview(makeRow(i, t))
            }
        }
    }

    @objc private func runTaskByIndex(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < currentTasks.count else { return }
        let task = currentTasks[idx]
        guard let taskId = task["id"] as? String else { return }
        guard let url = URL(string: "http://127.0.0.1:8787/api/tasks/\(taskId)/run") else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async {
                self.fetchTasks()
                self.pollResult(taskId: taskId, attempts: 0)
            }
        }.resume()
    }

    @objc private func editTaskByIndex(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < currentTasks.count else { return }
        let task = currentTasks[idx]
        guard let filename = task["filename"] as? String else { return }
        guard let url = URL(string: "http://127.0.0.1:8787/api/tasks/file/\(filename)") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let content = obj["content"] as? String else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                let alert = NSAlert()
                alert.messageText = "Edit \(filename)"
                let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 480, height: 300))
                let tv = NSTextView(frame: scroll.bounds)
                tv.string = content
                tv.isVerticallyResizable = true
                tv.autoresizingMask = [.width]
                if let c = tv.textContainer { c.widthTracksTextView = true }
                scroll.documentView = tv
                scroll.hasVerticalScroller = true
                alert.accessoryView = scroll
                let verifyBtn = NSButton(title: "Verify", target: nil, action: nil)
                verifyBtn.bezelStyle = .rounded
                verifyBtn.controlSize = .small
                let saveBtn = NSButton(title: "Save", target: nil, action: nil)
                saveBtn.bezelStyle = .rounded
                saveBtn.controlSize = .small
                saveBtn.isHidden = true
                let cancelBtn = NSButton(title: "Cancel", target: nil, action: nil)
                cancelBtn.bezelStyle = .rounded
                cancelBtn.controlSize = .small
                let btnRow = NSStackView(views: [verifyBtn, saveBtn, cancelBtn])
                btnRow.orientation = .horizontal
                btnRow.spacing = 6
                btnRow.translatesAutoresizingMaskIntoConstraints = false
                let container = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 340))
                scroll.frame = NSRect(x: 0, y: 40, width: 480, height: 300)
                container.addSubview(scroll)
                container.addSubview(btnRow)
                NSLayoutConstraint.activate([
                    btnRow.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
                    btnRow.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
                ])
                alert.accessoryView = container

                verifyBtn.target = self
                verifyBtn.action = #selector(self.verifyTaskText(_:))
                saveBtn.target = self
                saveBtn.action = #selector(self.saveTaskText(_:))
                cancelBtn.target = self
                cancelBtn.action = #selector(self.cancelTaskEdit(_:))

                // store context via tags on buttons
                verifyBtn.tag = 0
                // use a shared holder
                self.pendingEditFilename = filename
                self.pendingEditTextView = tv
                self.pendingEditSaveButton = saveBtn

                guard let window = self.window else { return }
                alert.beginSheetModal(for: window) { _ in }
            }
        }.resume()
    }

    private func fetchTasks() {
        tasksTextView.string = "Loading tasks...\n"
        guard let url = URL(string: "http://127.0.0.1:8787/api/tasks") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tasks = obj["tasks"] as? [[String: Any]] else {
                    self.tasksTextView.string = "noskill daemon not running on :8787.\nStart: sched serve --port 8787"
                    return
                }
                var lines: [String] = ["noskill scheduled tasks (max 50):", ""]
                for (i, t) in tasks.enumerated() {
                    let name = t["name"] as? String ?? "?"
                    let sched = t["schedule"] as? String ?? "?"
                    let enabled = t["enabled"] as? Bool ?? false
                    let status = t["status"] as? String ?? "?"
                    let next = t["next_run"] as? String ?? "?"
                    lines.append(String(format: "%2d  %@ %@", i+1, enabled ? "●" : "○", name))
                    lines.append("   schedule: \(sched)  status: \(status)")
                    lines.append("   next run: \(next)")
                    lines.append("")
                }
                self.currentTasks = tasks
                self.buildTaskRows(tasks: tasks)
                self.taskFilterPicker.removeAllItems()
                self.taskFilterPicker.addItem(withTitle: "All")
                self.taskFilterPicker.menu?.appearance = NSAppearance(named: .darkAqua)
                for t in tasks {
                    self.taskFilterPicker.addItem(withTitle: t["name"] as? String ?? "?")
                }
                self.taskFilterPicker.selectItem(at: 0)
                self.tasksTextView.string = lines.joined(separator: "\n")
            }
        }.resume()
    }

    @objc private func refreshTasksClicked(_ sender: Any?) { fetchTasks() }

    @objc private func newTaskClicked(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "New task name"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "my-task"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { resp in
            guard resp == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let filename = name + ".md"
            let content = "---\ntitle: \(name)\nschedule: \"0 9 * * *\"\nenabled: true\n---\n\nDescribe what this task should do.\n"
            guard let url = URL(string: "http://127.0.0.1:8787/api/tasks/file") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try? JSONSerialization.data(withJSONObject: ["filename": filename, "content": content])
            URLSession.shared.dataTask(with: req) { _, _, _ in
                DispatchQueue.main.async {
                    self.fetchTasks()
                }
            }.resume()
        }
    }

    @objc private func deleteTaskClicked(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Delete task number (1-\(min(currentTasks.count, 50)))"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "1"
        alert.accessoryView = field
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { resp in
            guard resp == .alertFirstButtonReturn else { return }
            guard let n = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  n >= 1, n <= self.currentTasks.count, n <= 50 else { return }
            let task = self.currentTasks[n-1]
            guard let filename = task["filename"] as? String else { return }
            guard let url = URL(string: "http://127.0.0.1:8787/api/tasks/file/\(filename)") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "DELETE"
            URLSession.shared.dataTask(with: req) { _, _, _ in
                DispatchQueue.main.async { self.fetchTasks() }
            }.resume()
        }
    }

    @objc private func runTaskClicked(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Run task number (1-\(min(currentTasks.count, 50)))"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "1"
        alert.accessoryView = field
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { resp in
            guard resp == .alertFirstButtonReturn else { return }
            guard let n = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  n >= 1, n <= self.currentTasks.count, n <= 50 else { return }
            let task = self.currentTasks[n-1]
            guard let taskId = task["id"] as? String else { return }
            guard let url = URL(string: "http://127.0.0.1:8787/api/tasks/\(taskId)/run") else { return }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            URLSession.shared.dataTask(with: req) { _, _, _ in
                DispatchQueue.main.async { self.fetchTasks() }
            }.resume()
        }
    }

    @objc private func runAllTasksClicked(_ sender: Any?) {
        for task in currentTasks {
            guard let taskId = task["id"] as? String else { continue }
            guard let url = URL(string: "http://127.0.0.1:8787/api/tasks/\(taskId)/run") else { continue }
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.fetchTasks() }
    }

    @objc private func saveTasksClicked(_ sender: Any?) {
        guard let url = URL(string: "http://127.0.0.1:8787/api/tasks") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data else { return }
            let dest = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FeatherA/saved_tasks.json")
            try? FileManager.default.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: dest, options: .atomic)
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = "Tasks saved"
                a.runModal()
            }
        }.resume()
    }

    @objc private func restoreTasksClicked(_ sender: Any?) {
        let src = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeatherA/saved_tasks.json")
        guard let data = try? Data(contentsOf: src),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tasks = obj["tasks"] as? [[String: Any]] else {
            let a = NSAlert(); a.messageText = "No saved tasks"; a.runModal(); return
        }
        // Recreate each task via POST
        for t in tasks {
            guard let filename = t["filename"] as? String else { continue }
            // fetch file content
            guard let url = URL(string: "http://127.0.0.1:8787/api/tasks/file/\(filename)") else { continue }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let content = o["content"] as? String else { return }
                guard let createURL = URL(string: "http://127.0.0.1:8787/api/tasks/file") else { return }
                var req = URLRequest(url: createURL)
                req.httpMethod = "POST"
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.httpBody = try? JSONSerialization.data(withJSONObject: ["filename": filename, "content": content])
                URLSession.shared.dataTask(with: req) { _, _, _ in }.resume()
            }.resume()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.fetchTasks() }
    }

    private func setupTaskButtons() {
        for v in taskButtonBar.arrangedSubviews { taskButtonBar.removeArrangedSubview(v); v.removeFromSuperview() }
        for v in taskBottomBar.arrangedSubviews { taskBottomBar.removeArrangedSubview(v); v.removeFromSuperview() }
        taskButtons.removeAll()
        let makeBtn = { (title: String?, symbol: String?, action: Selector) -> NSButton in
            let b: NSButton
            if let symbol = symbol {
                let img = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
                b = NSButton(image: img ?? NSImage(), target: self, action: action)
            } else {
                b = NSButton(title: title ?? "", target: self, action: action)
            }
            b.bezelStyle = .recessed
            b.controlSize = .mini
            return b
        }
        let defs: [(String?, String?, Selector)] = [("Add tasks", nil, #selector(newTaskClicked(_:))),
                                         ("Delete", nil, #selector(deleteTaskClicked(_:))),
                                         ("Run", nil, #selector(runTaskClicked(_:))),
                                         ("Run All", nil, #selector(runAllTasksClicked(_:))),
                                         (nil, "arrow.clockwise", #selector(refreshTasksClicked(_:))),
                                         ("Save", nil, #selector(saveTasksClicked(_:))),
                                         ("Restore", nil, #selector(restoreTasksClicked(_:)))]
        let buttons = defs.map { makeBtn($0.0, $0.1, $0.2) }
        taskButtons = buttons

        if panelPosition == "bottom" {
            // single row with all buttons
            let h = NSStackView(views: buttons)
            h.orientation = .horizontal
            h.spacing = 4
            h.alignment = .centerY
            taskButtonBar.addArrangedSubview(h)
            // hide bottom bar
            taskBottomBar.isHidden = true
        } else {
            // top: action buttons (single row, compact)
            let topBtns = Array(buttons.prefix(5))
            let h = NSStackView(views: topBtns)
            h.orientation = .horizontal
            h.spacing = 4
            h.alignment = .centerY
            taskButtonBar.addArrangedSubview(h)
            // bottom: Save + Restore
            for b in buttons.suffix(2) {
                taskBottomBar.addArrangedSubview(b)
            }
            taskBottomBar.isHidden = false
        }
        lastButtonWidth = self.bounds.width
    }

    @objc private func taskPicked(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < currentTasksForResults.count else { return }
        let task = currentTasksForResults[idx]
        guard let taskId = task["id"] as? String else { return }
        currentResultTaskId = taskId
        loadRunsForTask(taskId: taskId)
    }

    @objc private func runPicked(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0, idx < currentRuns.count else { return }
        guard let runId = currentRuns[idx]["run_id"] as? Int else { return }
        loadResult(runId: runId)
    }

    private func loadRunsForTask(taskId: String) {
        guard let url = URL(string: "http://127.0.0.1:8787/api/tasks/\(taskId)/runs") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.currentRuns = runs
                self.runPicker.removeAllItems()
                self.runPicker.menu?.appearance = NSAppearance(named: .darkAqua)
                for r in runs {
                    let started = r["started_at"] as? String ?? "?"
                    let status = r["status"] as? String ?? "?"
                    self.runPicker.addItem(withTitle: "\(started) [\(status)]")
                }
                if let latest = runs.first, let runId = latest["run_id"] as? Int {
                    self.runPicker.selectItem(at: 0)
                    self.loadResult(runId: runId)
                }
            }
        }.resume()
    }

    private func pollResult(taskId: String, attempts: Int) {
        guard attempts < 120 else { return }
        guard let url = URL(string: "http://127.0.0.1:8787/api/tasks/\(taskId)/runs") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let runs = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let latest = runs.first else { return }
            let status = latest["status"] as? String ?? "running"
            let runId = latest["run_id"] as? Int
            DispatchQueue.main.async {
                guard let self else { return }
                // show partial result while running
                if let rid = runId { self.loadResult(runId: rid) }
                if status == "running" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        self.pollResult(taskId: taskId, attempts: attempts + 1)
                    }
                } else {
                    self.fetchLatestResult(taskId: taskId)
                }
            }
        }.resume()
    }

    private func fetchResultsTasks() {
        guard let url = URL(string: "http://127.0.0.1:8787/api/tasks") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tasks = obj["tasks"] as? [[String: Any]] else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.currentTasksForResults = tasks
                self.taskPicker.removeAllItems()
                for (i, t) in tasks.enumerated() {
                    self.taskPicker.addItem(withTitle: "\(i+1). \(t["name"] as? String ?? "?")")
                }
                self.taskPicker.menu?.appearance = NSAppearance(named: .darkAqua)
                if let tid = self.currentResultTaskId, let idx = tasks.firstIndex(where: { ($0["id"] as? String) == tid }) {
                    self.taskPicker.selectItem(at: idx)
                    self.loadRunsForTask(taskId: tid)
                } else if let first = tasks.first, let tid = first["id"] as? String {
                    self.taskPicker.selectItem(at: 0)
                    self.loadRunsForTask(taskId: tid)
                }
            }
        }.resume()
    }

    private func fetchLatestResult(taskId: String) {
        currentResultTaskId = taskId
        // fetch task list for taskPicker
        guard let tasksURL = URL(string: "http://127.0.0.1:8787/api/tasks") else { return }
        URLSession.shared.dataTask(with: tasksURL) { [weak self] data, _, _ in
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tasks = obj["tasks"] as? [[String: Any]] else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.currentTasksForResults = tasks
                self.taskPicker.removeAllItems()
                for (i, t) in tasks.enumerated() {
                    let name = t["name"] as? String ?? "?"
                    self.taskPicker.addItem(withTitle: "\(i+1). \(name)")
                }
                if let idx = tasks.firstIndex(where: { ($0["id"] as? String) == taskId }) {
                    self.taskPicker.selectItem(at: idx)
                }
                self.loadRunsForTask(taskId: taskId)
            }
        }.resume()
    }

    private func loadResult(runId: Int) {
        guard let url = URL(string: "http://127.0.0.1:8787/api/runs/\(runId)/report") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            let report = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let run = self?.currentRuns.first(where: { ($0["run_id"] as? Int) == runId })
            var info: [String] = []
            if let r = run {
                info.append("Status: \(r["status"] as? String ?? "?")")
                info.append("Model: \(r["model"] as? String ?? "?")")
                info.append("Iterations: \(r["iterations"] as? Int ?? 0)")
                info.append("Tool calls: \(r["tool_calls"] as? Int ?? 0)")
                if let err = r["error"] as? String, !err.isEmpty { info.append("Error: \(err)") }
                if let started = r["started_at"] as? String { info.append("Started: \(started)") }
                if let finished = r["finished_at"] as? String { info.append("Finished: \(finished)") }
            }
            let header = info.joined(separator: "\n")
            let body = report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "(no report written)" : report
            let full = header + "\n\n" + body
            DispatchQueue.main.async {
                guard let self else { return }
                self.resultsTextView.string = full
                self.logsTextView.string += "\n=== Task Result ===\n" + full + "\n"
            }
        }.resume()
    }

    @objc private func taskFilterChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        if idx <= 0 {
            fetchTasks()
            return
        }
        let task = currentTasks[idx - 1]
        guard let taskId = task["id"] as? String else { return }
        var lines: [String] = []
        lines.append("Task: \(task["name"] as? String ?? "?")")
        lines.append("ID: \(taskId)")
        lines.append("Schedule: \(task["schedule"] as? String ?? "?")")
        lines.append("Enabled: \(task["enabled"] as? Bool ?? false)")
        lines.append("Status: \(task["status"] as? String ?? "?")")
        lines.append("Next run: \(task["next_run"] as? String ?? "?")")
        lines.append("Model: \(task["model"] as? String ?? "?")")
        tasksTextView.string = lines.joined(separator: "\n")
        let clip = tasksScrollView.contentView
        clip.scroll(to: NSPoint(x: 0, y: 0))
        tasksScrollView.reflectScrolledClipView(clip)
    }

    @objc private func verifyTaskText(_ sender: Any?) {
        guard let tv = pendingEditTextView else { return }
        let text = tv.string
        let ok = text.contains("---") && text.contains("id:") && text.contains("name:") && text.contains("schedule:") && text.split(separator: "\n").count > 6
        if ok {
            pendingEditSaveButton?.isHidden = false
            let a = NSAlert(); a.messageText = "Verified — format OK"; a.runModal()
        } else {
            let a = NSAlert(); a.messageText = "Verification failed — missing frontmatter (id, name, schedule) or body"; a.runModal()
        }
    }

    @objc private func saveTaskText(_ sender: Any?) {
        guard let filename = pendingEditFilename, let tv = pendingEditTextView else { return }
        let newContent = tv.string
        guard let putURL = URL(string: "http://127.0.0.1:8787/api/tasks/file/\(filename)") else { return }
        var req = URLRequest(url: putURL)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["content": newContent])
        URLSession.shared.dataTask(with: req) { _, _, _ in
            DispatchQueue.main.async { self.fetchTasks() }
        }.resume()
        if let window = self.window, let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
    }

    @objc private func cancelTaskEdit(_ sender: Any?) {
        if let window = self.window, let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
    }


    @objc private func scrollChatUp(_ s: Any?) { scrollByPage(chatScrollView, up: true) }
    @objc private func scrollChatDown(_ s: Any?) { scrollByPage(chatScrollView, up: false) }
    @objc private func scrollLogsUp(_ s: Any?) { scrollByPage(logsScrollView, up: true) }
    @objc private func scrollLogsDown(_ s: Any?) { scrollByPage(logsScrollView, up: false) }
    @objc private func scrollTasksUp(_ s: Any?) { scrollByPage(tasksScrollView, up: true) }
    @objc private func scrollTasksDown(_ s: Any?) { scrollByPage(tasksScrollView, up: false) }
    @objc private func scrollResultsUp(_ s: Any?) { scrollByPage(resultsScrollView, up: true) }
    @objc private func scrollResultsDown(_ s: Any?) { scrollByPage(resultsScrollView, up: false) }

    private func scrollByPage(_ sv: NSScrollView, up: Bool) {
        let clip = sv.contentView
        let page = clip.bounds.height * 0.8
        let cur = clip.bounds.origin.y
        let new = up ? max(0, cur - page) : cur + page
        clip.scroll(to: NSPoint(x: 0, y: new))
        sv.reflectScrolledClipView(clip)
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