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
    private let agentsToggle = NSButton()
    private let logsToggle = NSButton()
    private var agentsMode: Bool = false

    // Chat
    private let chatContainer = NSView()
    private let logsContainer = NSView()
    private let tasksContainer = NSView()
    private let tasksScrollView = NSScrollView()
    private let tasksTextView = NSTextView()
    private let taskRowsStack = FlippedStackView()
    private let tasksContentStack = FlippedStackView()
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
    private let taskPageBar = NSStackView()
    private var currentTaskPage: Int = 0
    private let tasksPerPage: Int = 5
    private var taskButtons: [NSButton] = []
    private var currentTasks: [[String: Any]] = []
    private var scheduleTimer: Timer?
    private var lastAutoRun: [String: Date] = [:]
    private var tabLabels: [String] = ["Ask"]
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
        logsToggle.translatesAutoresizingMaskIntoConstraints = false
        logsToggle.title = ">>"
        logsToggle.bezelStyle = .recessed
        logsToggle.controlSize = .mini
        logsToggle.contentTintColor = .white
        logsToggle.attributedTitle = NSAttributedString(string: ">>", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 10)])
        logsToggle.target = self
        logsToggle.action = #selector(toggleLogsMode(_:))
        tabControl.selectedSegment = 0
        tabControl.target = self
        tabControl.action = #selector(tabChanged(_:))
        tabControl.segmentStyle = .texturedSquare
        tabControl.appearance = NSAppearance(named: .darkAqua)

        refreshTabsFromSettings()
        NotificationCenter.default.addObserver(forName: Settings.changed, object: nil, queue: .main) { [weak self] _ in
            self?.refreshTabsFromSettings()
        }

        headerView.addSubview(iconView)
        headerView.addSubview(nameLabel)
        headerView.addSubview(tabControl)
        headerView.addSubview(logsToggle)

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
        sendButton.contentTintColor = NSColor.white
        sendButton.attributedTitle = NSAttributedString(string: "Send", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 11)])
        sendButton.target = self
        sendButton.action = #selector(sendChatNow)

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.title = "Close"
        closeButton.contentTintColor = NSColor.white
        closeButton.attributedTitle = NSAttributedString(string: "Close", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 11)])
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
        let logsAgents = NSButton(title: "Agents", target: self, action: #selector(toggleAgentsMode(_:)))
        logsUp.bezelStyle = .recessed; logsUp.controlSize = .mini
        logsDown.bezelStyle = .recessed; logsDown.controlSize = .mini
        logsAgents.bezelStyle = .recessed; logsAgents.controlSize = .mini
        logsAgents.toolTip = "Standalone local tasks (inside Logs)"
        logsNav.addArrangedSubview(logsUp)
        logsNav.addArrangedSubview(logsDown)
        logsNav.addArrangedSubview(logsAgents)
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
        taskRowsStack.translatesAutoresizingMaskIntoConstraints = false
        taskRowsStack.orientation = .vertical
        taskRowsStack.spacing = 2
        taskRowsStack.alignment = .leading
        tasksScrollView.documentView = taskRowsStack
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
        taskPageBar.orientation = .horizontal
        taskPageBar.spacing = 2
        taskPageBar.alignment = .centerY
        taskBottomBar.addArrangedSubview(taskPageBar)
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
        // buttons created in setupTaskButtons() called from configure
        NSLayoutConstraint.activate([
            taskButtonBar.topAnchor.constraint(equalTo: tasksContainer.topAnchor, constant: 2),
            taskButtonBar.leadingAnchor.constraint(equalTo: tasksContainer.leadingAnchor, constant: 8),
            taskButtonBar.trailingAnchor.constraint(equalTo: tasksContainer.trailingAnchor, constant: -8),
            taskButtonBar.heightAnchor.constraint(equalToConstant: 20),
            tasksScrollView.topAnchor.constraint(equalTo: taskButtonBar.bottomAnchor, constant: 2),
            tasksScrollView.leadingAnchor.constraint(equalTo: tasksContainer.leadingAnchor),
            tasksScrollView.trailingAnchor.constraint(equalTo: tasksContainer.trailingAnchor),
            tasksScrollView.bottomAnchor.constraint(equalTo: taskBottomBar.topAnchor, constant: -2),
            taskRowsStack.widthAnchor.constraint(equalTo: tasksScrollView.widthAnchor),
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

            tabControl.trailingAnchor.constraint(lessThanOrEqualTo: logsToggle.leadingAnchor, constant: -8),
            tabControl.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            logsToggle.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -8),
            logsToggle.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),

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
            resizeHandle.isHidden = false
            handleConstraints = [
                resizeHandle.topAnchor.constraint(equalTo: topAnchor),
                resizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
                resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
                resizeHandle.heightAnchor.constraint(equalToConstant: 6),
            ]
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

    private func updateAgentsToggleTitle() {}

    private func applyAgentsMode() {
        // Tabs are always available: Ask, Agents, Tasks, Results, Logs.
        if agentsMode { startBasicScheduler() } else { stopBasicScheduler() }
    }

    @objc private func toggleAgentsMode(_ sender: Any?) {
        agentsMode.toggle()
        if agentsMode {
            startBasicScheduler()
            if let idx = tabLabels.firstIndex(of: "Agents") ?? tabLabels.firstIndex(of: "Tasks") {
                tabControl.selectedSegment = idx
                tabChanged(tabControl)
            }
        } else {
            stopBasicScheduler()
        }
    }

    @objc func toggleLogsMode(_ sender: Any?) {
        // Shortcut: jump to Logs tab (or back to Ask).
        if let logsIdx = tabLabels.firstIndex(of: "Logs"), tabControl.selectedSegment == logsIdx {
            tabControl.selectedSegment = 0
        } else if let logsIdx = tabLabels.firstIndex(of: "Logs") {
            tabControl.selectedSegment = logsIdx
        }
        tabChanged(tabControl)
    }

    func refreshTabsFromSettings() {
        if !Settings.aiEnabled {
            tabLabels = ["Ask", "Logs"]
            chatTextView.string = "AI is off. Enable it in Settings → AI (uses local Ollama only)."
            stopBasicScheduler()
        } else {
            var labels = ["Ask"]
            if Settings.aiAgentsEnabled { labels.append("Agents") }
            if Settings.aiTasksEnabled { labels.append("Tasks") }
            labels.append("Results")
            labels.append("Logs")
            tabLabels = labels
        }
        tabControl.segmentCount = tabLabels.count
        for (i, l) in tabLabels.enumerated() { tabControl.setLabel(l, forSegment: i) }
        if tabControl.selectedSegment < 0 || tabControl.selectedSegment >= tabLabels.count { tabControl.selectedSegment = 0 }
        tabChanged(tabControl)
    }

    @objc func tabChanged(_ sender: NSSegmentedControl) {
        let seg = sender.selectedSegment
        guard seg >= 0, seg < tabLabels.count else { return }
        let label = tabLabels[seg]
        chatContainer.isHidden = label != "Ask"
        tasksContainer.isHidden = !(label == "Agents" || label == "Tasks")
        resultsContainer.isHidden = label != "Results"
        logsContainer.isHidden = label != "Logs"
        let onLogs = label == "Logs"
        logsToggle.attributedTitle = NSAttributedString(string: onLogs ? "<<" : ">>", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 10)])
        if label == "Agents" { agentsMode = true; startBasicScheduler(); fetchTasks() }
        if label == "Tasks" { fetchTasks() }
        if label == "Results" { fetchResultsTasks() }
    }

    var onHide: (() -> Void)?
    var onResize: ((CGFloat) -> Void)?
    /// Always grab fresh page contents as known context before each Ask.
    var fetchPageText: (() async -> String)?

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
        let totalPages = max(1, Int(ceil(Double(tasks.count) / Double(tasksPerPage))))
        if currentTaskPage >= totalPages { currentTaskPage = totalPages - 1 }
        if currentTaskPage < 0 { currentTaskPage = 0 }
        let start = currentTaskPage * tasksPerPage
        let end = min(start + tasksPerPage, tasks.count)
        let pageTasks = Array(tasks[start..<end])
        let pageOffset = start
        updateTaskPageControls(totalPages: totalPages)
        let makeRow: (Int, [String: Any]) -> NSStackView = { globalIndex, t in
            let i = globalIndex
            let name = t["name"] as? String ?? "?"
            let enabled = t["enabled"] as? Bool ?? false
            let sched = t["schedule"] as? String ?? "?"
            let status = t["status"] as? String ?? "?"
            let next = t["next_run"] as? String ?? "?"
            let row = NSStackView()
            row.orientation = .horizontal
            row.spacing = 6
            row.alignment = .top
            let numLabel = NSTextField(labelWithString: String(format: "%2d", i+1))
            numLabel.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
            numLabel.alignment = .right
            numLabel.textColor = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
            numLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            numLabel.setContentHuggingPriority(.required, for: .horizontal)
            numLabel.widthAnchor.constraint(equalToConstant: 22).isActive = true
            let label = NSTextField(labelWithString: String(format: "%@ %@   %@ · %@ · %@", enabled ? "●" : "○", name, sched, status, next))
            label.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            // test: 3 max rows per task
            label.lineBreakMode = .byWordWrapping
            label.maximumNumberOfLines = 3
            let rowColor: NSColor
            switch status {
            case "running": rowColor = NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.2, alpha: 1.0)
            case "failed": rowColor = NSColor(calibratedRed: 1.0, green: 0.2, blue: 0.2, alpha: 1.0)
            default: rowColor = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
            }
            label.textColor = rowColor
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
            row.addArrangedSubview(numLabel)
            row.addArrangedSubview(label)
            row.addArrangedSubview(spacer)
            row.addArrangedSubview(editBtn)
            row.addArrangedSubview(runBtn)
            return row
        }
        let availableWidth = self.bounds.width > 0 ? self.bounds.width : (panelPosition == "bottom" ? 1280 : 400)
        let ncols = min(3, max(1, Int(availableWidth / 360)))
        if ncols > 1 {
            var cols: [NSStackView] = (0..<ncols).map { _ in
                let st = NSStackView()
                st.orientation = .vertical
                st.spacing = 2
                st.alignment = .leading
                st.setContentHuggingPriority(.defaultLow, for: .horizontal)
                return st
            }
            for (i, t) in pageTasks.enumerated() {
                cols[i % ncols].addArrangedSubview(makeRow(pageOffset + i, t))
            }
            let container = NSStackView(views: cols)
            container.orientation = .horizontal
            container.spacing = 8
            container.alignment = .top
            container.distribution = .fillEqually
            taskRowsStack.addArrangedSubview(container)
        } else {
            for (i, t) in pageTasks.enumerated() {
                taskRowsStack.addArrangedSubview(makeRow(pageOffset + i, t))
            }
        }
    }

    @objc private func runTaskByIndex(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < currentTasks.count else { return }
        runLocalTask(at: idx)
    }

    private func runLocalTask(at idx: Int) {
        guard idx >= 0, idx < currentTasks.count else { return }
        let task = currentTasks[idx]
        let taskId = task["id"] as? String ?? "task"
        let name = task["name"] as? String ?? taskId
        let model = task["model"] as? String ?? ServicesConfig.load().answerModel
        let filename = task["filename"] as? String
        let content = (filename.flatMap { try? String(contentsOf: localTasksDirectory().appendingPathComponent($0), encoding: .utf8) })
            ?? (task["content"] as? String) ?? "Run task: \(name)"
        appendLog("[task] Running \(name) (standalone, model=\(model))")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await LocalModel(config: ServicesConfig.load()).runPrompt(content, model: model)
                let run: [String: Any] = [
                    "task_id": taskId, "task_name": name, "model": model,
                    "status": "success", "started_at": ISO8601DateFormatter().string(from: Date()),
                    "output": result
                ]
                self.saveLocalRun(taskId: taskId, run: run)
                self.resultsTextView.string = "Task: \(name)\nStatus: success\nModel: \(model)\n\n\(result)"
                self.appendLog("[task] \(name): success")
                self.tabControl.selectedSegment = 3
                self.tabChanged(self.tabControl)
                self.fetchTasks()
            } catch {
                self.saveLocalRun(taskId: taskId, run: ["task_id": taskId, "task_name": name, "status": "failed", "error": "\(error)", "output": ""])
                self.resultsTextView.string = "Task: \(name)\nStatus: failed\n\n\(error)"
                self.appendLog("[task] \(name): failed — \(error)")
                self.tabControl.selectedSegment = 3
                self.tabChanged(self.tabControl)
                self.fetchTasks()
            }
        }
    }

    private func saveLocalRun(taskId: String, run: [String: Any]) {
        let safe = taskId.replacingOccurrences(of: "/", with: "-")
        let url = localRunsDirectory().appendingPathComponent("\(safe).last.json")
        if let data = try? JSONSerialization.data(withJSONObject: run, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: url, options: .atomic)
        }
    }

    // Basic in-app scheduling (standalone, runs only while FeatherA is open; requires only Ollama).
    private func startBasicScheduler() {
        stopBasicScheduler()
        appendLog("[scheduler] Basic in-app scheduler started (checks every 60s)")
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkScheduledTasks() }
        }
        checkScheduledTasks()
    }

    private func stopBasicScheduler() {
        scheduleTimer?.invalidate()
        scheduleTimer = nil
    }

    private func checkScheduledTasks() {
        let tasks = loadLocalTasks()
        let now = Date()
        for (i, t) in tasks.enumerated() {
            let enabled = t["enabled"] as? Bool ?? false
            guard enabled else { continue }
            let sched = (t["schedule"] as? String ?? "manual").trimmingCharacters(in: .whitespacesAndNewlines)
            guard sched.lowercased() != "manual", !sched.isEmpty, sched != "-" else { continue }
            let id = t["id"] as? String ?? (t["filename"] as? String ?? "task\(i)")
            if isTaskDue(schedule: sched, id: id, now: now) {
                lastAutoRun[id] = now
                appendLog("[scheduler] Due: \(t["name"] as? String ?? id) (\(sched))")
                runLocalTask(at: i)
            }
        }
    }

    private func isTaskDue(schedule: String, id: String, now: Date) -> Bool {
        if let last = lastAutoRun[id], now.timeIntervalSince(last) < 55 { return false }
        let s = schedule.lowercased()
        let cal = Calendar.current
        if s == "@hourly" { return cal.component(.minute, from: now) == 0 }
        if s == "@daily" { return cal.component(.hour, from: now) == 9 && cal.component(.minute, from: now) == 0 }
        if s.hasPrefix("@every") {
            let parts = s.split(separator: " ")
            if parts.count >= 2 {
                let token = String(parts[1])
                if let n = Int(token.filter({ $0.isNumber })), n > 0 {
                    let interval: TimeInterval = token.contains("h") ? Double(n) * 3600 : Double(n) * 60
                    if let last = lastAutoRun[id] { return now.timeIntervalSince(last) >= interval }
                    return true
                }
            }
        }
        // minimal cron: "M H * * *" (daily at H:M local)
        let c = schedule.split(separator: " ").map(String.init)
        if c.count >= 5, c[2] == "*", c[3] == "*", c[4] == "*" {
            if let m = Int(c[0]), let h = Int(c[1]) {
                return cal.component(.hour, from: now) == h && cal.component(.minute, from: now) == m
            }
        }
        return false // unsupported cron -> drop (no auto-run)
    }


    @objc private func editTaskByIndex(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < currentTasks.count else { return }
        let task = currentTasks[idx]
        guard let filename = task["filename"] as? String else { return }
        let fileURL = localTasksDirectory().appendingPathComponent(filename)
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? (task["content"] as? String) ?? ""
        let alert = NSAlert()
        alert.messageText = "Edit \(filename) (standalone)"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
        let tv = NSTextView(frame: scroll.bounds)
        tv.string = content
        tv.isEditable = true
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        if let c = tv.textContainer { c.widthTracksTextView = true }
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        alert.accessoryView = scroll
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            try? tv.string.write(to: fileURL, atomically: true, encoding: .utf8)
            self.fetchTasks()
        }
    }

    private func fetchTasks() {
        // Standalone baseline: local task files only (no external scheduler/agents).
        let tasks = loadLocalTasks()
        var lines: [String] = ["Standalone local tasks (Ollama + browser):", "Dir: \(localTasksDirectory().path)", ""]
        for (i, t) in tasks.enumerated() {
            let name = t["name"] as? String ?? "?"
            let sched = t["schedule"] as? String ?? "-"
            let enabled = t["enabled"] as? Bool ?? false
            let status = t["status"] as? String ?? "idle"
            let model = t["model"] as? String ?? "granite4:3b"
            lines.append(String(format: "%2d  %@ %@  [%@]  schedule: %@  model: %@", i+1, enabled ? "●" : "○", name, status, sched, model))
        }
        if tasks.isEmpty { lines.append("(no tasks yet — use Add tasks to create one locally)") }
        self.currentTasks = tasks
        self.currentTaskPage = 0
        self.buildTaskRows(tasks: tasks)
        self.tasksTextView.string = lines.joined(separator: "\n")
    }

    @objc private func refreshTasksClicked(_ sender: Any?) { fetchTasks() }

    @objc private func newTaskClicked(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "New local task (standalone)"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "my-task"
        alert.accessoryView = field
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            let safe = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let filename = safe + ".md"
            let id = safe
            let content = """
            ---
            id: \(id)
            name: \(name)
            schedule: "manual"
            enabled: true
            model: granite4:3b
            ---

            Describe what this task should do. When run, this text is sent to the local Ollama model as the workflow prompt.
            """
            let url = self.localTasksDirectory().appendingPathComponent(filename)
            try? content.write(to: url, atomically: true, encoding: .utf8)
            self.fetchTasks()
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
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            guard let n = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  n >= 1, n <= self.currentTasks.count else { return }
            let task = self.currentTasks[n-1]
            guard let filename = task["filename"] as? String else { return }
            let url = self.localTasksDirectory().appendingPathComponent(filename)
            try? FileManager.default.removeItem(at: url)
            self.fetchTasks()
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
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            guard let n = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  n >= 1, n <= self.currentTasks.count else { return }
            self.runLocalTask(at: n - 1)
        }
    }

    @objc private func runAllTasksClicked(_ sender: Any?) {
        for i in 0..<currentTasks.count { runLocalTask(at: i) }
    }

    // Standalone: local tasks only (Ollama + browser, no external scheduler/agents).
    private func localTasksDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeatherA/tasks", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func localRunsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeatherA/runs", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func parseFrontmatter(_ content: String) -> [String: String] {
        var out: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return out }
        for line in lines.dropFirst() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t == "---" { break }
            if let idx = t.firstIndex(of: ":") {
                let k = String(t[..<idx]).trimmingCharacters(in: .whitespaces)
                var v = String(t[t.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
                if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 { v = String(v.dropFirst().dropLast()) }
                out[k] = v
            }
        }
        return out
    }

    private func loadLocalTasks() -> [[String: Any]] {
        let dir = localTasksDirectory()
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles])) ?? []
        let md = files.filter { $0.pathExtension == "md" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        var tasks: [[String: Any]] = []
        for (i, url) in md.enumerated() {
            let filename = url.lastPathComponent
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            let fmatter = parseFrontmatter(content)
            let id = fmatter["id"] ?? filename.replacingOccurrences(of: ".md", with: "")
            let name = fmatter["name"] ?? id
            let schedule = fmatter["schedule"] ?? "-"
            let enabled = (fmatter["enabled"] ?? "true").lowercased() != "false"
            let model = fmatter["model"] ?? "granite4:3b"
            tasks.append([
                "number": i + 1,
                "id": id,
                "name": name,
                "filename": filename,
                "schedule": schedule,
                "enabled": enabled,
                "status": "idle",
                "last_model": model,
                "model": model,
                "next_run": "-",
                "content": content,
            ])
        }
        return tasks
    }

    private func taskBackupsDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeatherA/task-backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func listTaskBackups() -> [URL] {
        let dir = taskBackupsDirectory()
        let fm = FileManager.default
        var files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        files = files.filter { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("saved_tasks_") }
        files.sort { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da > db
        }
        // include legacy latest file if present
        let legacy = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FeatherA/saved_tasks.json")
        if fm.fileExists(atPath: legacy.path) && !files.contains(legacy) {
            files.append(legacy)
        }
        return files
    }

    @objc private func saveTasksClicked(_ sender: Any?) {
        // Standalone: back up local task files (no external scheduler).
        let tasks = loadLocalTasks()
        var files: [String: String] = [:]
        for t in tasks {
            if let filename = t["filename"] as? String, let content = t["content"] as? String {
                files[filename] = content
            } else if let filename = t["filename"] as? String {
                let url = localTasksDirectory().appendingPathComponent(filename)
                if let c = try? String(contentsOf: url, encoding: .utf8) { files[filename] = c }
            }
        }
        let formatter = ISO8601DateFormatter()
        let savedAt = formatter.string(from: Date())
        let backup: [String: Any] = ["version": 2, "standalone": true, "saved_at": savedAt, "tasks": tasks, "files": files]
        do {
            let out = try JSONSerialization.data(withJSONObject: backup, options: [.prettyPrinted, .sortedKeys])
            let ts = savedAt.replacingOccurrences(of: ":", with: "-")
            let dir = taskBackupsDirectory()
            let hist = dir.appendingPathComponent("saved_tasks_\(ts).json")
            try out.write(to: hist, options: .atomic)
            let latest = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("FeatherA/saved_tasks.json")
            try? FileManager.default.createDirectory(at: latest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try out.write(to: latest, options: .atomic)
            showTaskAlert("Tasks saved", "Saved \(tasks.count) local task(s), \(files.count) file(s).\nBackup: \(hist.lastPathComponent)")
        } catch {
            showTaskAlert("Save failed", error.localizedDescription)
        }
    }

    @objc private func restoreTasksClicked(_ sender: Any?) {
        let backups = listTaskBackups()
        guard !backups.isEmpty else {
            showTaskAlert("No saved tasks", "No task backups found. Use Save first.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Restore tasks"
        alert.informativeText = "Choose a backup to restore. Task file contents from the backup will be posted to the scheduler."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 360, height: 24), pullsDown: false)
        let df = DateFormatter()
        df.dateStyle = .short
        df.timeStyle = .medium
        for url in backups {
            let name = url.lastPathComponent
            let date = (try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey]).contentModificationDate) ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate)
            let label = date.map { "\(name) (\(df.string(from: $0)))" } ?? name
            picker.addItem(withTitle: label)
            picker.lastItem?.representedObject = url
        }
        alert.accessoryView = picker
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .alertFirstButtonReturn,
                  let url = picker.selectedItem?.representedObject as? URL else { return }
            self?.restoreTasks(from: url)
        }
    }

    private func restoreTasks(from src: URL) {
        // Standalone: restore task files locally (no external scheduler).
        do {
            let data = try Data(contentsOf: src)
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tasks = obj["tasks"] as? [[String: Any]] else {
                showTaskAlert("Restore failed", "Backup format not recognized.")
                return
            }
            let files = obj["files"] as? [String: String] ?? [:]
            var ok = 0
            var failed: [String] = []
            let dir = localTasksDirectory()
            for t in tasks {
                guard let filename = t["filename"] as? String else { continue }
                if let content = files[filename] {
                    do {
                        try content.write(to: dir.appendingPathComponent(filename), atomically: true, encoding: .utf8)
                        ok += 1
                    } catch {
                        failed.append(filename)
                    }
                } else {
                    failed.append(filename)
                }
            }
            fetchTasks()
            var msg = "Restored \(ok)/\(tasks.count) local task(s) from \(src.lastPathComponent)."
            if !failed.isEmpty { msg += "\nMissing/failed content: \(failed.joined(separator: ", "))" }
            showTaskAlert("Restore complete", msg)
        } catch {
            showTaskAlert("Restore failed", error.localizedDescription)
        }
    }

    private func showTaskAlert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.runModal()
    }

    private func updateTaskPageControls(totalPages: Int) {
        for v in taskPageBar.arrangedSubviews { taskPageBar.removeArrangedSubview(v); v.removeFromSuperview() }
        taskPageBar.orientation = .horizontal
        taskPageBar.spacing = 2
        taskPageBar.alignment = .centerY
        let total = max(1, totalPages)
        currentTaskPage = min(max(0, currentTaskPage), total - 1)
        let page = currentTaskPage + 1
        let showPrev = page > 1
        let showNext = page < total
        let makeBtn: (String, Selector, Bool) -> NSButton = { title, action, enabled in
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .recessed
            b.controlSize = .mini
            b.isEnabled = enabled
            b.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: enabled ? NSColor.white : NSColor.gray, .font: NSFont.systemFont(ofSize: 10)])
            return b
        }
        if showPrev {
            taskPageBar.addArrangedSubview(makeBtn("<", #selector(taskPagePrev(_:)), true))
        }
        let label = NSTextField(labelWithString: "\(page)")
        label.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        label.textColor = .white
        taskPageBar.addArrangedSubview(label)
        if showNext {
            taskPageBar.addArrangedSubview(makeBtn(">", #selector(taskPageNext(_:)), true))
        }
    }

    @objc private func taskPagePrev(_ sender: Any?) {
        guard currentTaskPage > 0 else { return }
        currentTaskPage -= 1
        buildTaskRows(tasks: currentTasks)
    }

    @objc private func taskPageNext(_ sender: Any?) {
        let total = max(1, Int(ceil(Double(currentTasks.count) / Double(tasksPerPage))))
        guard currentTaskPage < total - 1 else { return }
        currentTaskPage += 1
        buildTaskRows(tasks: currentTasks)
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
                b.attributedTitle = NSAttributedString(string: title ?? "", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 10)])
            }
            b.bezelStyle = .recessed
            b.controlSize = .mini
            b.contentTintColor = .white
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

        updateTaskPageControls(totalPages: max(1, Int(ceil(Double(currentTasks.count) / Double(tasksPerPage)))))

        if panelPosition == "bottom" {
            // top: all action buttons
            let h = NSStackView(views: buttons)
            h.orientation = .horizontal
            h.spacing = 4
            h.alignment = .centerY
            taskButtonBar.addArrangedSubview(h)
            // bottom: centered page nav
            let leftSpacer = NSView()
            leftSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            let rightSpacer = NSView()
            rightSpacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
            taskBottomBar.addArrangedSubview(leftSpacer)
            taskBottomBar.addArrangedSubview(taskPageBar)
            taskBottomBar.addArrangedSubview(rightSpacer)
            taskBottomBar.isHidden = false
        } else {
            // top: action buttons (single row, compact)
            let topBtns = Array(buttons.prefix(5))
            let h = NSStackView(views: topBtns)
            h.orientation = .horizontal
            h.spacing = 4
            h.alignment = .centerY
            taskButtonBar.addArrangedSubview(h)
            // bottom: Save + Restore + < page# > beside Restore
            for b in buttons.suffix(2) {
                taskBottomBar.addArrangedSubview(b)
            }
            taskBottomBar.addArrangedSubview(taskPageBar)
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
                if self.logsMode {
                    self.logsMode = false
                    self.tabControl.isHidden = false
                    self.logsToggle.attributedTitle = NSAttributedString(string: ">>", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 10)])
                }
                self.tabControl.selectedSegment = 2
                self.tabChanged(self.tabControl)
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
        if let fetchPageText {
            let fresh = await fetchPageText()
            if !fresh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pageText = fresh
                appendLog("Page context refreshed: \(fresh.count) chars")
            }
        }
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

/// A vertically-flipped NSStackView so its content pins to the top of a scroll view.
final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}
