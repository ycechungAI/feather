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
    private let taskButtonBar = NSStackView()
    private let taskBottomBar = NSStackView()
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
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

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
        tabControl.segmentCount = 3
        tabControl.setLabel("Ask", forSegment: 0)
        tabControl.setLabel("Logs", forSegment: 1)
        tabControl.setLabel("Tasks", forSegment: 2)
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

        // Tasks
        tasksContainer.translatesAutoresizingMaskIntoConstraints = false
        tasksScrollView.translatesAutoresizingMaskIntoConstraints = false
        tasksScrollView.hasVerticalScroller = true
        tasksScrollView.borderType = .bezelBorder
        tasksScrollView.documentView = tasksTextView
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
        taskButtonBar.translatesAutoresizingMaskIntoConstraints = false
        taskButtonBar.orientation = .vertical
        taskButtonBar.spacing = 4
        taskButtonBar.alignment = .leading
        taskBottomBar.translatesAutoresizingMaskIntoConstraints = false
        taskBottomBar.orientation = .horizontal
        taskBottomBar.spacing = 6
        taskBottomBar.alignment = .centerY
        // buttons created in setupTaskButtons() called from configure
        NSLayoutConstraint.activate([
            taskButtonBar.topAnchor.constraint(equalTo: tasksContainer.topAnchor, constant: 4),
            taskButtonBar.leadingAnchor.constraint(equalTo: tasksContainer.leadingAnchor, constant: 8),
            taskButtonBar.trailingAnchor.constraint(equalTo: tasksContainer.trailingAnchor, constant: -8),
            tasksScrollView.topAnchor.constraint(equalTo: taskButtonBar.bottomAnchor, constant: 4),
            tasksScrollView.leadingAnchor.constraint(equalTo: tasksContainer.leadingAnchor),
            tasksScrollView.trailingAnchor.constraint(equalTo: tasksContainer.trailingAnchor),
            tasksScrollView.bottomAnchor.constraint(equalTo: taskBottomBar.topAnchor, constant: -4),
            taskBottomBar.leadingAnchor.constraint(equalTo: tasksContainer.leadingAnchor, constant: 8),
            taskBottomBar.trailingAnchor.constraint(equalTo: tasksContainer.trailingAnchor, constant: -8),
            taskBottomBar.bottomAnchor.constraint(equalTo: tasksContainer.bottomAnchor, constant: -4),
            taskBottomBar.heightAnchor.constraint(equalToConstant: 28),
        ])

        // Assemble
        addSubview(headerView)
        addSubview(chatContainer)
        addSubview(logsContainer)
        addSubview(tasksContainer)
        logsContainer.isHidden = true
        tasksContainer.isHidden = true

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: topAnchor),
            headerView.leadingAnchor.constraint(equalTo: leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: 44),

            iconView.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 8),
            iconView.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: tabControl.leadingAnchor, constant: -16),

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
            handleConstraints = [
                resizeHandle.topAnchor.constraint(equalTo: topAnchor),
                resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
                resizeHandle.bottomAnchor.constraint(equalTo: bottomAnchor),
                resizeHandle.widthAnchor.constraint(equalToConstant: 6),
            ]
        case "bottom":
            handleConstraints = [
                resizeHandle.topAnchor.constraint(equalTo: topAnchor),
                resizeHandle.leadingAnchor.constraint(equalTo: leadingAnchor),
                resizeHandle.trailingAnchor.constraint(equalTo: trailingAnchor),
                resizeHandle.heightAnchor.constraint(equalToConstant: 6),
            ]
        default:
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
                delta = panStartLocation - loc.y
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
        chatContainer.isHidden = sender.selectedSegment != 0
        logsContainer.isHidden = sender.selectedSegment != 1
        tasksContainer.isHidden = sender.selectedSegment != 2
        if sender.selectedSegment == 2 {
            fetchTasks()
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
                for (i, t) in tasks.prefix(50).enumerated() {
                    let name = t["name"] as? String ?? "?"
                    let sched = t["schedule"] as? String ?? "?"
                    let enabled = t["enabled"] as? Bool ?? false
                    let status = t["status"] as? String ?? "?"
                    let next = t["next_run"] as? String ?? "?"
                    lines.append("\(i+1). \(enabled ? "●" : "○") \(name)")
                    lines.append("   schedule: \(sched)  status: \(status)")
                    lines.append("   next run: \(next)")
                    lines.append("")
                }
                self.currentTasks = tasks
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
                DispatchQueue.main.async { self.fetchTasks() }
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
        let topDefs: [(String?, String?, Selector)] = [("Add tasks", nil, #selector(newTaskClicked(_:))),
                                         ("Delete", nil, #selector(deleteTaskClicked(_:))),
                                         ("Run", nil, #selector(runTaskClicked(_:))),
                                         (nil, "arrow.clockwise", #selector(refreshTasksClicked(_:)))]
        let bottomDefs: [(String?, Selector)] = [("Save", #selector(saveTasksClicked(_:))),
                                                 ("Restore", #selector(restoreTasksClicked(_:)))]
        let topButtons = topDefs.map { (title, symbol, action) -> NSButton in
            let b: NSButton
            if let symbol = symbol {
                let img = NSImage(systemSymbolName: symbol, accessibilityDescription: "Refresh")
                b = NSButton(image: img ?? NSImage(), target: self, action: action)
            } else {
                b = NSButton(title: title ?? "", target: self, action: action)
            }
            b.bezelStyle = .rounded
            b.controlSize = .small
            return b
        }
        taskButtons = topButtons
        let width = self.bounds.width > 0 ? self.bounds.width : 380
        let perRow: Int
        if width >= 700 { perRow = 4 }
        else if width >= 380 { perRow = 2 }
        else { perRow = 2 }
        var row: [NSButton] = []
        var rows: [[NSButton]] = []
        for b in topButtons {
            row.append(b)
            if row.count >= perRow { rows.append(row); row = [] }
        }
        if !row.isEmpty { rows.append(row) }
        for r in rows {
            let h = NSStackView(views: r)
            h.orientation = .horizontal
            h.spacing = 4
            h.alignment = .centerY
            taskButtonBar.addArrangedSubview(h)
        }
        for (title, action) in bottomDefs {
            let b = NSButton(title: title ?? "", target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            taskBottomBar.addArrangedSubview(b)
        }
        lastButtonWidth = width
    }

    override func layout() {
        super.layout()
        if abs(bounds.width - lastButtonWidth) > 40 {
            setupTaskButtons()
        }
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