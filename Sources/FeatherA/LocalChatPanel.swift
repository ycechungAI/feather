import AppKit
import WebKit

/// The chat view shown in the browser window's side panel (dockable left/right/bottom via Settings).
/// Embedded in BrowserWindowController's content area instead of a floating popup.
@MainActor
final class LocalChatView: NSView, WKScriptMessageHandler {
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
    private let researchContainer = NSView()
    private var researchWebView: WKWebView?
    private var researchPopupHelper: AnyObject?
    private let logsContainer = NSView()
    private let tasksContainer = NSView()
    private let agentsContainer = NSView()
    private let tasksScrollView = NSScrollView()
    private let tasksTextView = NSTextView()
    private let taskRowsStack = FlippedStackView()
    private let tasksContentStack = FlippedStackView()
    private let agentsScrollView = NSScrollView()
    private let agentsTextView = NSTextView()
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
    var pendingEditScheduleField: NSTextField?
    var pendingEditNextRunField: NSTextField?
    var pendingEditEnabledBox: NSButton?
    private var currentTasksForResults: [[String: Any]] = []
    private var logsMode: Bool = false
    private let taskButtonBar = NSStackView()
    private let taskBottomBar = NSStackView()
    private let taskPageBar = NSStackView()
    private var currentTaskPage: Int = 0
    private var tasksPerPage: Int { panelPosition == "bottom" ? 9 : 10 }
    private var taskButtons: [NSButton] = []
    private var currentTasks: [[String: Any]] = []
    private var scheduleTimer: Timer?
    private var lastAutoRun: [String: Date] = [:]
    private var runningTaskIDs: Set<String> = []
    private var tabLabels: [String] = ["Ask"]
    private let chatScrollView = NSScrollView()
    private let chatTextView = NSTextView()
    private let inputRow = NSView()
    private let inputStack = NSStackView()
    private let inputField = NSTextField()
    private let sendButton = NSButton()
    private let closeButton = NSButton()
    private let researchButton = NSButton()

    // Resize handle
    private let resizeHandle = NSView()
    private var inputRowHeightConstraint: NSLayoutConstraint?
    private var inputFieldMinHeightConstraint: NSLayoutConstraint?
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
        chatScrollView.hasVerticalScroller = true
        chatScrollView.hasHorizontalScroller = false
        chatScrollView.autohidesScrollers = false
        chatScrollView.scrollerKnobStyle = .light
        chatScrollView.borderType = .bezelBorder
        chatScrollView.drawsBackground = true
        chatScrollView.backgroundColor = NSColor.black
        chatScrollView.documentView = chatTextView
        chatTextView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        chatTextView.minSize = NSSize(width: 0, height: 0)
        chatTextView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        chatTextView.autoresizingMask = [.width]
        chatTextView.isEditable = false
        chatTextView.isSelectable = true
        chatTextView.drawsBackground = true
        chatTextView.backgroundColor = NSColor.black
        chatTextView.textColor = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
        chatTextView.font = .systemFont(ofSize: 13)
        chatTextView.isVerticallyResizable = true
        chatTextView.isHorizontallyResizable = false
        if let container = chatTextView.textContainer {
            container.widthTracksTextView = true
            container.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
        }

        inputRow.translatesAutoresizingMaskIntoConstraints = false
        let irh = inputRow.heightAnchor.constraint(equalToConstant: 104)
        irh.isActive = true
        inputRowHeightConstraint = irh

        inputStack.translatesAutoresizingMaskIntoConstraints = false
        inputStack.orientation = .vertical
        inputStack.alignment = .leading
        inputStack.spacing = 6

        inputField.translatesAutoresizingMaskIntoConstraints = false
        inputField.placeholderString = "Ask about this page"
        inputField.usesSingleLineMode = false
        inputField.lineBreakMode = .byWordWrapping
        inputField.maximumNumberOfLines = 4
        if let cell = inputField.cell as? NSTextFieldCell {
            cell.wraps = true
            cell.isScrollable = true
        }
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

        researchButton.translatesAutoresizingMaskIntoConstraints = false
        researchButton.title = "Research"
        researchButton.bezelStyle = .recessed
        researchButton.controlSize = .small
        researchButton.target = self
        researchButton.action = #selector(openResearchPopup(_:))
        researchButton.toolTip = "Research (Orcastrator): web search, inline citations; extended thinking off for now"
        researchButton.isHidden = !Settings.aiResearchEnabled

        let buttonRow = NSStackView()
        buttonRow.translatesAutoresizingMaskIntoConstraints = false
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 6
        buttonRow.addArrangedSubview(researchButton)
        buttonRow.addArrangedSubview(chatUp)
        buttonRow.addArrangedSubview(chatDown)
        buttonRow.addArrangedSubview(NSView()) // spacer
        buttonRow.addArrangedSubview(sendButton)
        buttonRow.addArrangedSubview(closeButton)

        // Layout: history (chatScrollView) above, textbox (inputField) above Send/Close row.
        inputStack.addArrangedSubview(inputField)
        inputStack.addArrangedSubview(buttonRow)

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
            inputStack.topAnchor.constraint(equalTo: inputRow.topAnchor, constant: 6),
            inputStack.bottomAnchor.constraint(equalTo: inputRow.bottomAnchor, constant: -6),
            inputStack.leadingAnchor.constraint(equalTo: inputRow.leadingAnchor, constant: 8),
            inputStack.trailingAnchor.constraint(equalTo: inputRow.trailingAnchor, constant: -8),
            inputField.widthAnchor.constraint(equalTo: inputStack.widthAnchor),
            { let c = inputField.heightAnchor.constraint(greaterThanOrEqualToConstant: 58); self.inputFieldMinHeightConstraint = c; return c }(),
            buttonRow.widthAnchor.constraint(equalTo: inputStack.widthAnchor),
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
        logsAgents.toolTip = "Open Agents tab (standalone scheduler — separate from Tasks)"
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

        // Agents (standalone local scheduler/agent view — separate from Tasks CRUD)
        agentsContainer.translatesAutoresizingMaskIntoConstraints = false
        agentsContainer.appearance = NSAppearance(named: .darkAqua)
        agentsScrollView.translatesAutoresizingMaskIntoConstraints = false
        agentsScrollView.hasVerticalScroller = false
        agentsScrollView.borderType = .bezelBorder
        agentsScrollView.documentView = agentsTextView
        agentsTextView.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        agentsTextView.autoresizingMask = [.width]
        agentsTextView.isEditable = false
        agentsTextView.isSelectable = true
        agentsTextView.drawsBackground = true
        agentsTextView.backgroundColor = NSColor.black
        agentsTextView.textColor = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
        agentsTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        agentsTextView.isVerticallyResizable = true
        if let container = agentsTextView.textContainer { container.widthTracksTextView = true }
        agentsTextView.string = "Standalone Agents (local Ollama + browser). Scheduler runs only while FeatherA is open.\nUse Tasks tab for full task CRUD."
        let agentsBar = NSStackView()
        agentsBar.translatesAutoresizingMaskIntoConstraints = false
        agentsBar.orientation = .horizontal
        agentsBar.spacing = 6
        let agentsRefresh = NSButton(title: "Refresh", target: self, action: #selector(refreshAgentsClicked(_:)))
        agentsRefresh.bezelStyle = .recessed; agentsRefresh.controlSize = .small
        let agentsCheck = NSButton(title: "Check now", target: self, action: #selector(checkAgentsNowClicked(_:)))
        agentsCheck.bezelStyle = .recessed; agentsCheck.controlSize = .small
        let setSched = NSButton(title: "Set schedule", target: self, action: #selector(setScheduleClicked(_:)))
        setSched.bezelStyle = .recessed; setSched.controlSize = .small
        let toggleEn = NSButton(title: "Enable/Disable", target: self, action: #selector(toggleAgentEnabledClicked(_:)))
        toggleEn.bezelStyle = .recessed; toggleEn.controlSize = .small
        agentsBar.addArrangedSubview(agentsRefresh)
        agentsBar.addArrangedSubview(agentsCheck)
        agentsBar.addArrangedSubview(setSched)
        agentsBar.addArrangedSubview(toggleEn)
        agentsContainer.addSubview(agentsBar)
        agentsContainer.addSubview(agentsScrollView)
        NSLayoutConstraint.activate([
            agentsBar.topAnchor.constraint(equalTo: agentsContainer.topAnchor, constant: 4),
            agentsBar.leadingAnchor.constraint(equalTo: agentsContainer.leadingAnchor, constant: 8),
            agentsBar.trailingAnchor.constraint(lessThanOrEqualTo: agentsContainer.trailingAnchor, constant: -8),
            agentsBar.heightAnchor.constraint(equalToConstant: 22),
            agentsScrollView.topAnchor.constraint(equalTo: agentsBar.bottomAnchor, constant: 4),
            agentsScrollView.leadingAnchor.constraint(equalTo: agentsContainer.leadingAnchor),
            agentsScrollView.trailingAnchor.constraint(equalTo: agentsContainer.trailingAnchor),
            agentsScrollView.bottomAnchor.constraint(equalTo: agentsContainer.bottomAnchor),
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


        // Research (Orcastrator) — opt-in tab beside Ask. Loads local Orcastrator web UI when available.
        // Defaults requested: web search on, inline citations on, extended thinking unchecked.
        researchContainer.translatesAutoresizingMaskIntoConstraints = false
        researchContainer.wantsLayer = true
        researchContainer.layer?.backgroundColor = NSColor(white: 0.06, alpha: 1).cgColor
        let rwcfg = WKWebViewConfiguration()
        let graniteScript = WKUserScript(source: """
        (function(){
          var DEFAULT_MODEL = 'granite4:3b';
          function is1B(v){ return /(^|[^0-9])1b([^0-9]|$)/i.test((v||'').trim()); }
          function sortModels(){
            try{
              var m=document.getElementById('model'); if(!m || m.dataset.featherSorting==='1') return;
              var opts=Array.prototype.slice.call(m.options||[]); if(opts.length<2) return;
              var cur=m.value;
              var sorted=opts.slice().sort(function(a,b){
                var av=(a.value||a.text||'').trim(), bv=(b.value||b.text||'').trim();
                return av.localeCompare(bv, undefined, {numeric:true, sensitivity:'base'});
              });
              var same=true; for(var i=0;i<opts.length;i++){ if(opts[i].value!==sorted[i].value){ same=false; break; } }
              if(same) return;
              m.dataset.featherSorting='1';
              sorted.forEach(function(o){ m.appendChild(o); });
              if(cur){ try{ m.value=cur; }catch(e){} }
              setTimeout(function(){ try{ m.dataset.featherSorting='0'; }catch(e){} }, 0);
            }catch(e){ try{ var m2=document.getElementById('model'); if(m2) m2.dataset.featherSorting='0'; }catch(e2){} }
          }
          function pickGranite(){
            try {
              var m = document.getElementById('model');
              if(!m) return;
              // Auto-select granite4:3b default; never auto-select 1B.
              var exact=null, fallback=null;
              for(var i=0;i<m.options.length;i++){
                var opt=m.options[i]; var v=(opt.value||opt.text||'').trim(); var vl=v.toLowerCase();
                if(v===DEFAULT_MODEL || vl.indexOf('granite4:3b')===0){ exact=opt; break; }
                if(!fallback && !is1B(v) && v) fallback=opt;
              }
              var found = exact || fallback;
              if(found){
                if(m.value !== found.value){ m.value = found.value; m.dispatchEvent(new Event('change',{bubbles:true})); }
              } else if(m.options.length===0 || !m.value){
                try {
                  var exists = false;
                  for(var j=0;j<m.options.length;j++){ if((m.options[j].value||'')===DEFAULT_MODEL) exists=true; }
                  if(!exists){ var o=document.createElement('option'); o.value=DEFAULT_MODEL; o.text=DEFAULT_MODEL; m.add(o,0); }
                  m.value = DEFAULT_MODEL;
                } catch(ex){}
              }
            } catch(e){}
          }
          function applyDefaults(){
            try {
              var w=document.getElementById('webResearch'); if(w){ w.checked=true; w.dispatchEvent(new Event('change')); }
              var c=document.getElementById('citations'); if(c){ c.checked=true; }
              var e=document.getElementById('extended'); if(e){ e.checked=false; }
              var t=document.getElementById('modeToggle'); if(t && !t.__featherInit){ t.checked=true; t.dispatchEvent(new Event('change')); t.__featherInit=true; }
            } catch(e){}
            sortModels();
            pickGranite();
          }
          document.addEventListener('DOMContentLoaded', applyDefaults);
          window.addEventListener('load', applyDefaults);
          setInterval(applyDefaults, 800);
          var obs = new MutationObserver(function(){ var mm=document.getElementById('model'); if(mm && mm.dataset.featherSorting==='1') return; applyDefaults(); });
          function watch(){ var m=document.getElementById('model'); if(m) obs.observe(m,{childList:true,subtree:true,attributes:true}); else setTimeout(watch, 300); }
          watch();
        })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        rwcfg.userContentController.addUserScript(graniteScript)
        let researchBridge = WKUserScript(source: BrowserWindowController.researchBridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        rwcfg.userContentController.addUserScript(researchBridge)
        rwcfg.userContentController.add(self, name: ResearchBridge.handlerName)
        let rwv = WKWebView(frame: .zero, configuration: rwcfg)
        rwv.translatesAutoresizingMaskIntoConstraints = false
        rwv.setValue(false, forKey: "drawsBackground")
        researchWebView = rwv
        let rstatus = NSTextField(labelWithString: "Research: web-based UI with Swift native bridge (no runtime Python server). Opens in a browser tab for best results.")
        rstatus.translatesAutoresizingMaskIntoConstraints = false
        rstatus.font = NSFont.systemFont(ofSize: 11)
        rstatus.textColor = .secondaryLabelColor
        rstatus.lineBreakMode = .byWordWrapping
        rstatus.maximumNumberOfLines = 3
        researchContainer.addSubview(rstatus)
        researchContainer.addSubview(rwv)
        NSLayoutConstraint.activate([
            rstatus.topAnchor.constraint(equalTo: researchContainer.topAnchor, constant: 6),
            rstatus.leadingAnchor.constraint(equalTo: researchContainer.leadingAnchor, constant: 8),
            rstatus.trailingAnchor.constraint(equalTo: researchContainer.trailingAnchor, constant: -8),
            rwv.topAnchor.constraint(equalTo: rstatus.bottomAnchor, constant: 4),
            rwv.leadingAnchor.constraint(equalTo: researchContainer.leadingAnchor),
            rwv.trailingAnchor.constraint(equalTo: researchContainer.trailingAnchor),
            rwv.bottomAnchor.constraint(equalTo: researchContainer.bottomAnchor),
        ])
        // Load bundled Orcastrator UI (Swift bridge; no :8400 server required).
        if let url = OrcastratorService.bundledUIURL() {
            rwv.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        // Apply defaults after load attempts (web search on, inline citations on, extended thinking unchecked).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak rwv] in
            let js = """
            try {
              var t=document.getElementById('modeToggle'); if(t){t.checked=true; t.dispatchEvent(new Event('change'));}
              var w=document.getElementById('webResearch'); if(w){w.checked=true; w.dispatchEvent(new Event('change'));}
              var c=document.getElementById('citations'); if(c){c.checked=true;}
              var e=document.getElementById('extended'); if(e){e.checked=false;}
              var cw=document.getElementById('chatWebResearch'); if(cw){cw.checked=true;}
            } catch(e){}
            """
            rwv?.evaluateJavaScript(js, completionHandler: nil)
        }

        // Assemble
        addSubview(headerView)
        addSubview(chatContainer)
        addSubview(researchContainer)
        addSubview(logsContainer)
        addSubview(tasksContainer)
        addSubview(agentsContainer)
        addSubview(resultsContainer)
        researchContainer.isHidden = true
        logsContainer.isHidden = true
        tasksContainer.isHidden = true
        agentsContainer.isHidden = true
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

            researchContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            researchContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            researchContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            researchContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            logsContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            logsContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            logsContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            logsContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            tasksContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            tasksContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            tasksContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            tasksContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

            agentsContainer.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            agentsContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            agentsContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            agentsContainer.bottomAnchor.constraint(equalTo: bottomAnchor),

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
        updateInputLayoutForPosition()
        history = Settings.saveChatHistory ? Self.loadHistory() : []
        inputField.stringValue = ""
        render()
        appendLog("Panel opened. Page text: \(pageText.count) chars.")
        setupHandle()
        setupTaskButtons()
    }


    private func updateInputLayoutForPosition() {
        // Bottom panel: 1 row for typing. Left/right: 3 rows at least.
        if panelPosition == "bottom" {
            inputRowHeightConstraint?.constant = 52
            inputFieldMinHeightConstraint?.constant = 22
            inputField.maximumNumberOfLines = 1
        } else {
            inputRowHeightConstraint?.constant = 104
            inputFieldMinHeightConstraint?.constant = 58
            inputField.maximumNumberOfLines = 4
        }
        // Rebuild task pagination for the new page size.
        if !currentTasks.isEmpty { buildTaskRows(tasks: currentTasks) }
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
            let minSize: CGFloat = (panelPosition == "left" || panelPosition == "right") ? 460 : 180
            let newSize = max(minSize, panStartSize + delta)
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
        // Open the standalone Agents tab (separate from Tasks).
        if let idx = tabLabels.firstIndex(of: "Agents") {
            agentsMode = true
            startBasicScheduler()
            tabControl.selectedSegment = idx
            tabChanged(tabControl)
        } else {
            // Agents tab not enabled in Settings — show message via logs and do not switch to Tasks.
            appendLog("[agents] Agents tab is not enabled. Turn on Settings → AI → Agents tab.")
            showTaskAlert("Agents tab disabled", "Agents is separate from Tasks. Enable Settings → AI → Agents tab to use the standalone Agents/scheduler view.")
        }
    }

    @objc func toggleLogsMode(_ sender: Any?) {
        // Logs accessed via >> button (not a tab).
        logsMode.toggle()
        logsToggle.attributedTitle = NSAttributedString(string: logsMode ? "<<" : ">>", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 10)])
        if logsMode {
            chatContainer.isHidden = true
            researchContainer.isHidden = true
            tasksContainer.isHidden = true
            agentsContainer.isHidden = true
            resultsContainer.isHidden = true
            logsContainer.isHidden = false
        } else {
            logsContainer.isHidden = true
            tabChanged(tabControl)
        }
    }

    func refreshTabsFromSettings() {
        if !Settings.aiEnabled {
            tabLabels = ["Ask"]
            chatTextView.string = "AI is off. Enable it in Settings → AI (uses local Ollama only)."
            stopBasicScheduler()
        } else {
            var labels = ["Ask"]
            if Settings.aiResearchEnabled { labels.append("Research") }
            if Settings.aiAgentsEnabled { labels.append("Agents") }
            if Settings.aiTasksEnabled { labels.append("Tasks") }
            labels.append("Results")
            tabLabels = labels
        }
        researchButton.isHidden = true
        tabControl.segmentCount = tabLabels.count
        for (i, l) in tabLabels.enumerated() { tabControl.setLabel(l, forSegment: i) }
        if tabControl.selectedSegment < 0 || tabControl.selectedSegment >= tabLabels.count { tabControl.selectedSegment = 0 }
        tabChanged(tabControl)
    }

    @objc func tabChanged(_ sender: NSSegmentedControl) {
        let seg = sender.selectedSegment
        guard seg >= 0, seg < tabLabels.count else { return }
        // Switching tabs exits Logs overlay (Logs is accessed via >>).
        if logsMode {
            logsMode = false
            logsToggle.attributedTitle = NSAttributedString(string: ">>", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 10)])
        }
        let label = tabLabels[seg]
        chatContainer.isHidden = label != "Ask"
        researchContainer.isHidden = label != "Research"
        // Tasks = task definitions/CRUD. Agents = scheduler view (same local tasks, easier schedule/auto-run control).
        tasksContainer.isHidden = label != "Tasks"
        agentsContainer.isHidden = label != "Agents"
        resultsContainer.isHidden = label != "Results"
        logsContainer.isHidden = true
        if label == "Research" {
            // Open bundled Orcastrator/Research UI in a new browser tab (web-based, no runtime Python).
            // APIs are handled by the Swift native bridge (calls local Ollama).
            if let url = OrcastratorService.bundledUIURL() {
                onOpenURL?(url)
                appendLog("[research] Opened bundled Research UI (Swift/native bridge, no Python runtime)")
            } else {
                appendLog("[research] Bundled Research UI not found")
            }
            captureResearchSummaryToResults()
            if let askIdx = tabLabels.firstIndex(of: "Ask") {
                tabControl.selectedSegment = askIdx
                chatContainer.isHidden = false
                researchContainer.isHidden = true
            }
            return
        }
        if label == "Agents" { agentsMode = true; startBasicScheduler(); refreshAgentsView() }
        if label == "Tasks" { agentsMode = false; fetchTasks() }
        if label == "Results" { fetchResultsTasks(); captureResearchSummaryToResults() }
    }


    private func captureResearchSummaryToResults() {
        // Keep report on Research tab and copy a summary into Results.
        guard let rwv = researchWebView else { return }
        let js = """
        (function(){
          try {
            var topic = (document.getElementById('topic')||{}).value || '';
            var report = document.getElementById('report');
            var text = report ? (report.innerText || report.textContent || '') : '';
            return JSON.stringify({topic: topic, text: text, visible: !!(report && text.trim().length>0 && !document.getElementById('reportPanel')?.classList.contains('hidden'))});
          } catch(e){ return JSON.stringify({topic:'', text:'', visible:false}); }
        })();
        """
        rwv.evaluateJavaScript(js) { [weak self] result, _ in
            guard let self, let json = result as? String, let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let visible = obj["visible"] as? Bool, visible,
                  let text = obj["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let topic = (obj["topic"] as? String) ?? ""
            let excerpt = String(text.prefix(1200))
            let summary = "=== Research Report (Orcastrator) ===\nTopic: \(topic.isEmpty ? "(unknown)" : topic)\n\n\(excerpt)\n\n(Full report remains on the Research tab.)"
            DispatchQueue.main.async {
                self.resultsTextView.string = summary
                self.appendLog("[research] Summary copied to Results")
            }
        }
    }


    private func applyResearchDefaults() {
        // Research tab (Orcastrator UI): research mode toggle, topic input, model selection,
        // extended thinking OFF by default, web search ON, inline citations ON, then Generate report.
        guard let rwv = researchWebView else { return }
        if rwv.url == nil, let url = URL(string: "http://127.0.0.1:8400/") {
            rwv.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5))
        }
        let js = """
        (function(){
          function apply(){
            try {
              var t=document.getElementById('modeToggle'); if(t && !t.__featherSet){ t.checked=true; t.dispatchEvent(new Event('change')); t.__featherSet=true; }
              var w=document.getElementById('webResearch'); if(w){ w.checked=true; w.dispatchEvent(new Event('change')); }
              var c=document.getElementById('citations'); if(c){ c.checked=true; }
              var e=document.getElementById('extended'); if(e){ e.checked=false; }
              var cw=document.getElementById('chatWebResearch'); if(cw){ cw.checked=true; }
              var m=document.getElementById('model');
              if(m){
                var has=false;
                for(var i=0;i<m.options.length;i++){ var v=m.options[i].value||m.options[i].text||''; if(v==='granite4:3b'){ has=true; break; } }
                if(has){ m.value='granite4:3b'; }
                else if(m.options.length===0 || m.dataset.featherGraniteTried!=='1'){
                  try { var o=document.createElement('option'); o.value='granite4:3b'; o.text='granite4:3b (default)'; m.add(o,0); m.value='granite4:3b'; m.dataset.featherGraniteTried='1'; } catch(ex){}
                }
              }
            } catch(e){}
          }
          apply();
          if(!window.__featherResearchDefaults){ window.__featherResearchDefaults=setInterval(apply, 1200); setTimeout(function(){try{clearInterval(window.__featherResearchDefaults);}catch(e){}}, 15000); }
        })();
        """
        let run: () -> Void = { [weak rwv] in rwv?.evaluateJavaScript(js, completionHandler: nil) }
        run()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { run() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { run() }
    }

            @objc private func openResearchPopup(_ sender: Any?) {
        // Between Send/Close: popup for options (what to search and run). Results in same Ask area.
        guard Settings.aiEnabled else {
            showTaskAlert("AI off", "Enable Settings → AI to use Research.")
            return
        }
        if !Settings.aiResearchEnabled {
            showTaskAlert("Research disabled", "Enable Settings → AI → Research tab (Orcastrator), then use Research here. Requires Orcastrator web on http://127.0.0.1:8400.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Research (Orcastrator)"
        alert.informativeText = "Choose what to search and run. Results show in the Ask panel (same area)."
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 132))
        let topicLabel = NSTextField(labelWithString: "Search / topic:")
        topicLabel.frame = NSRect(x: 0, y: 104, width: 90, height: 18)
        let topicField = NSTextField(frame: NSRect(x: 94, y: 100, width: 420, height: 24))
        topicField.placeholderString = "What do you want to research?"
        let webBox = NSButton(checkboxWithTitle: "Web search", target: nil, action: nil)
        webBox.frame = NSRect(x: 94, y: 74, width: 110, height: 18); webBox.state = .on
        let citeBox = NSButton(checkboxWithTitle: "Inline citations", target: nil, action: nil)
        citeBox.frame = NSRect(x: 210, y: 74, width: 120, height: 18); citeBox.state = .on
        let thinkBox = NSButton(checkboxWithTitle: "Extended thinking", target: nil, action: nil)
        thinkBox.frame = NSRect(x: 336, y: 74, width: 140, height: 18); thinkBox.state = .off
        let hint = NSTextField(labelWithString: "Defaults: web search on, inline citations on, extended thinking off. Runs via local Orcastrator (:8400).")
        hint.frame = NSRect(x: 94, y: 46, width: 420, height: 22)
        hint.font = NSFont.systemFont(ofSize: 10); hint.textColor = .secondaryLabelColor
        hint.lineBreakMode = .byWordWrapping; hint.maximumNumberOfLines = 2
        container.addSubview(topicLabel); container.addSubview(topicField)
        container.addSubview(webBox); container.addSubview(citeBox); container.addSubview(thinkBox)
        container.addSubview(hint)
        alert.accessoryView = container
        alert.addButton(withTitle: "Run (results in Ask panel)")      // .alertFirstButtonReturn
        alert.addButton(withTitle: "Open Research UI (info popup)")   // .alertSecondButtonReturn
        alert.addButton(withTitle: "Cancel")                          // .alertThirdButtonReturn
        let win = self.window ?? NSApp.keyWindow
        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard let self else { return }
            if resp == .alertThirdButtonReturn { return }
            if resp == .alertSecondButtonReturn {
                let info = NSAlert()
                info.messageText = "Research UI (info)"
                info.informativeText = "Full Orcastrator controls/info. Results can be shown in the Ask panel via the Research button."
                let wv = WKWebView(frame: NSRect(x: 0, y: 0, width: 760, height: 520))
                if let u = URL(string: "http://127.0.0.1:8400/") { wv.load(URLRequest(url: u)) }
                info.accessoryView = wv
                info.addButton(withTitle: "Close")
                let apply = {
                    let js = "try{var t=document.getElementById('modeToggle');if(t){t.checked=true;t.dispatchEvent(new Event('change'));}var w=document.getElementById('webResearch');if(w){w.checked=\(webBox.state == .on ? "true":"false");w.dispatchEvent(new Event('change'));}var c=document.getElementById('citations');if(c){c.checked=\(citeBox.state == .on ? "true":"false");}var e=document.getElementById('extended');if(e){e.checked=\(thinkBox.state == .on ? "true":"false");}}catch(e){}"
                    wv.evaluateJavaScript(js, completionHandler: nil)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: apply)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: apply)
                if let w = self.window ?? NSApp.keyWindow { info.beginSheetModal(for: w) { _ in } } else { info.runModal() }
                return
            }
            let topic = topicField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            self.showResearchResultsInPanel(url: URL(string: "http://127.0.0.1:8400/"))
            guard !topic.isEmpty, let rwv = self.researchWebView else { return }
            let escaped = topic.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'").replacingOccurrences(of: "\n", with: " ")
            let web = webBox.state == .on ? "true" : "false"
            let cite = citeBox.state == .on ? "true" : "false"
            let think = thinkBox.state == .on ? "true" : "false"
            let js = "try{var topic=document.getElementById('topic');if(topic){topic.value='\(escaped)';topic.dispatchEvent(new Event('input',{bubbles:true}));}var w=document.getElementById('webResearch');if(w){w.checked=\(web);w.dispatchEvent(new Event('change'));}var c=document.getElementById('citations');if(c){c.checked=\(cite);}var e=document.getElementById('extended');if(e){e.checked=\(think);}var t=document.getElementById('modeToggle');if(t){t.checked=true;t.dispatchEvent(new Event('change'));}var form=document.getElementById('form')||document.querySelector('form');if(form){form.requestSubmit?form.requestSubmit():form.dispatchEvent(new Event('submit',{bubbles:true,cancelable:true}));}}catch(err){}"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak rwv] in rwv?.evaluateJavaScript(js, completionHandler: nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak rwv] in rwv?.evaluateJavaScript(js, completionHandler: nil) }
            self.appendLog("[research] Running: \(topic) (web=\(web), citations=\(cite), extended=\(think))")
        }
        if let win { alert.beginSheetModal(for: win, completionHandler: handle) } else { handle(alert.runModal()) }
    }

    private func showResearchResultsInPanel(url: URL?) {
        // "Same area for results": show Orcastrator web UI in the Ask/chat results area.
        guard let url else { return }
        // Replace chat scroll/history area with research webview inside chatContainer.
        chatScrollView.isHidden = true
        if let rwv = researchWebView {
            rwv.removeFromSuperview()
            rwv.translatesAutoresizingMaskIntoConstraints = false
            chatContainer.addSubview(rwv)
            NSLayoutConstraint.activate([
                rwv.topAnchor.constraint(equalTo: chatContainer.topAnchor),
                rwv.leadingAnchor.constraint(equalTo: chatContainer.leadingAnchor),
                rwv.trailingAnchor.constraint(equalTo: chatContainer.trailingAnchor),
                rwv.bottomAnchor.constraint(equalTo: inputRow.topAnchor),
            ])
            rwv.isHidden = false
            if rwv.url == nil || rwv.url?.host != url.host { rwv.load(URLRequest(url: url)) }
            applyResearchDefaults()
        }
        appendLog("[research] Showing Research results in Ask panel (same area). Close/reopen Ask or switch view to restore chat history.")
    }


    var onHide: (() -> Void)?
    var onResize: ((CGFloat) -> Void)?
    /// Always grab fresh page contents as known context before each Ask.
    var fetchPageText: (() async -> String)?
    /// Open a URL in a new browser tab (e.g. Research/Orcastrator).
    var onOpenURL: ((URL) -> Void)?

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
        scrollChatToBottom()
    }

    private func scrollChatToBottom() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let tc = self.chatTextView.textContainer {
                self.chatTextView.layoutManager?.ensureLayout(for: tc)
            }
            self.chatTextView.scrollToEndOfDocument(nil)
            let clip = self.chatScrollView.contentView
            let maxY = max(0, self.chatTextView.frame.height - clip.bounds.height)
            clip.scroll(to: NSPoint(x: 0, y: maxY))
            self.chatScrollView.reflectScrolledClipView(clip)
        }
    }

    func appendLog(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        logsTextView.string += "[\(timestamp)] \(message)\n"
        let clip = logsScrollView.contentView
        let maxY = max(0, logsTextView.frame.height - clip.bounds.height)
        clip.scroll(to: NSPoint(x: 0, y: maxY))
        logsScrollView.reflectScrolledClipView(clip)
    }

    private func buildTaskRows(tasks: [[String: Any]]) {
        for v in taskRowsStack.arrangedSubviews { taskRowsStack.removeArrangedSubview(v); v.removeFromSuperview() }
        let availableWidth = self.bounds.width > 0 ? self.bounds.width : (panelPosition == "bottom" ? 1280 : 460)
        let ncols = min(3, max(1, Int(availableWidth / 360)))
        // 3 columns = 3x3 (9); 2 columns = 2x5 (10); 1 column = 10.
        let pageSize = (ncols == 3) ? 9 : 10
        let totalPages = max(1, Int(ceil(Double(tasks.count) / Double(pageSize))))
        if currentTaskPage >= totalPages { currentTaskPage = totalPages - 1 }
        if currentTaskPage < 0 { currentTaskPage = 0 }
        let start = currentTaskPage * pageSize
        let end = min(start + pageSize, tasks.count)
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
            // Task number always green. Disabled = grey; running = yellow; failed = bright red; rest/success = green.
            let statusColor: NSColor
            if !enabled {
                statusColor = NSColor(calibratedWhite: 0.55, alpha: 1.0)
            } else {
                switch status {
                case "running":
                    statusColor = NSColor(calibratedRed: 1.0, green: 1.0, blue: 0.2, alpha: 1.0)
                case "failed":
                    statusColor = NSColor(calibratedRed: 1.0, green: 0.15, blue: 0.15, alpha: 1.0)
                default: // success, idle, or unknown
                    statusColor = NSColor(calibratedRed: 0.2, green: 1.0, blue: 0.2, alpha: 1.0)
                }
            }
            label.textColor = statusColor
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
        let model = task["model"] as? String ?? "granite4:3b"
        let filename = task["filename"] as? String
        let content = (filename.flatMap { try? String(contentsOf: localTasksDirectory().appendingPathComponent($0), encoding: .utf8) })
            ?? (task["content"] as? String) ?? "Run task: \(name)"
        runningTaskIDs.insert(taskId)
        fetchTasks() // refresh rows to show running (yellow)
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
                self.runningTaskIDs.remove(taskId)
                self.resultsTextView.string = "Task: \(name)\nStatus: success\nModel: \(model)\n\n\(result)"
                self.appendLog("[task] \(name): success")
                if let r = self.tabLabels.firstIndex(of: "Results") {
                    self.tabControl.selectedSegment = r
                    self.tabChanged(self.tabControl)
                }
                self.fetchTasks()
                self.refreshAgentsView()
            } catch {
                self.saveLocalRun(taskId: taskId, run: ["task_id": taskId, "task_name": name, "status": "failed", "error": "\(error)", "output": ""])
                self.runningTaskIDs.remove(taskId)
                self.resultsTextView.string = "Task: \(name)\nStatus: failed\n\n\(error)"
                self.appendLog("[task] \(name): failed — \(error)")
                if let r = self.tabLabels.firstIndex(of: "Results") {
                    self.tabControl.selectedSegment = r
                    self.tabChanged(self.tabControl)
                }
                self.fetchTasks()
                self.refreshAgentsView()
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


    @objc private func refreshAgentsClicked(_ sender: Any?) { refreshAgentsView() }
    @objc private func checkAgentsNowClicked(_ sender: Any?) {
        appendLog("[agents] Manual scheduler check")
        checkScheduledTasks()
        refreshAgentsView()
    }

    func refreshAgentsView() {
        // Agents = scheduler (how/when local tasks execute). Same local tasks, scheduler-focused view.
        // Safety boundary: no autonomous browser/agent disk skills (no arbitrary save/copy/file control).
        // Only explicit user actions (Save/Restore backups) and app-managed task/run storage are used.
        let tasks = loadLocalTasks()
        let sched = scheduleTimer != nil ? "RUNNING — checks every 60s, runs due tasks automatically (local Ollama only)" : "stopped"
        var lines: [String] = []
        lines.append("AGENTS / SCHEDULER (standalone, local Ollama + browser)")
        lines.append("Think of Agents as the scheduler: change how and when each task is executed.")
        lines.append("Safety: agents are scoped to scheduling/local runs — no browser-controlled disk skills (no arbitrary save/copy).")
        lines.append("• Set schedule/model/enabled here. • Tasks tab: edit task content/definitions.")
        lines.append("")
        lines.append("Scheduler: \(sched)")
        lines.append("Task store: \(localTasksDirectory().path)")
        lines.append("")
        if tasks.isEmpty {
            lines.append("No local tasks yet. Create tasks in the Tasks tab, then set schedule/model here.")
        } else {
            lines.append("Local tasks (\(tasks.count)) — schedule/auto-run status:")
            for (i, t) in tasks.enumerated() {
                let name = t["name"] as? String ?? "?"
                let status = t["status"] as? String ?? "idle"
                let schedule = t["schedule"] as? String ?? "manual"
                let enabled = t["enabled"] as? Bool ?? false
                let mark = status == "running" ? "[RUNNING yellow]" : (status == "failed" ? "[FAILED red]" : (status == "success" ? "[OK green]" : "[idle green]"))
                let auto = (schedule.lowercased() != "manual" && schedule != "-" && enabled) ? "auto" : "manual/off"
                lines.append(String(format: "%2d. %@ %@  %@  when=%@  %@  how/model=%@", i+1, enabled ? "●" : "○", name, mark, schedule, auto, t["model"] as? String ?? "?"))
            }
            lines.append("")
            lines.append("Use 'Set schedule' to change when/how (schedule, model) by task #. Use 'Enable/Disable' to control auto-run.")
        }
        lines.append("")
        lines.append("Backups are explicit user actions and stored separately (not shown as tasks/results).")
        agentsTextView.string = lines.joined(separator: "\n")
    }

    @objc private func setScheduleClicked(_ sender: Any?) {
        // Agents/scheduler view: make it easy to change when (schedule/enabled) and how (model) each task runs.
        let tasks = loadLocalTasks()
        guard !tasks.isEmpty else { showTaskAlert("No tasks", "Create a task in the Tasks tab first."); return }
        let alert = NSAlert()
        alert.messageText = "Change how/when task runs (scheduler)"
        alert.informativeText = "Enter task number, schedule, and model. Schedules: manual, @hourly, @daily (09:00), @every 15m, @every 1h, or simple daily cron 'M H * * *'."
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 92))
        let numLabel = NSTextField(labelWithString: "Task #:")
        numLabel.frame = NSRect(x: 0, y: 66, width: 60, height: 20)
        let numField = NSTextField(frame: NSRect(x: 64, y: 64, width: 60, height: 24))
        numField.placeholderString = "1"
        let schedLabel = NSTextField(labelWithString: "Schedule:")
        schedLabel.frame = NSRect(x: 0, y: 36, width: 60, height: 20)
        let schedField = NSTextField(frame: NSRect(x: 64, y: 34, width: 290, height: 24))
        schedField.placeholderString = "@hourly / @daily / @every 30m / manual"
        let modelLabel = NSTextField(labelWithString: "Model:")
        modelLabel.frame = NSRect(x: 0, y: 6, width: 60, height: 20)
        let modelField = NSTextField(frame: NSRect(x: 64, y: 4, width: 290, height: 24))
        modelField.stringValue = "granite4:3b"
        container.addSubview(numLabel); container.addSubview(numField)
        container.addSubview(schedLabel); container.addSubview(schedField)
        container.addSubview(modelLabel); container.addSubview(modelField)
        alert.accessoryView = container
        alert.addButton(withTitle: "Apply")
        alert.addButton(withTitle: "Cancel")
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            guard let n = Int(numField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  n >= 1, n <= tasks.count else {
                self.showTaskAlert("Invalid task number", "Enter a number from 1 to \(tasks.count)."); return
            }
            let task = tasks[n-1]
            guard let filename = task["filename"] as? String else { return }
            let schedule = schedField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let fileURL = self.localTasksDirectory().appendingPathComponent(filename)
            guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
            if !schedule.isEmpty { content = self.updateFrontmatter(content, key: "schedule", value: "\"\(schedule)\"") }
            if !model.isEmpty { content = self.updateFrontmatter(content, key: "model", value: model) }
            // scheduling implies enabled by default unless manual
            if !schedule.isEmpty && schedule.lowercased() != "manual" {
                content = self.updateFrontmatter(content, key: "enabled", value: "true")
            }
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                self.appendLog("[agents] Updated \(filename): schedule=\(schedule.isEmpty ? "(unchanged)" : schedule), model=\(model.isEmpty ? "(unchanged)" : model)")
                self.fetchTasks()
                self.refreshAgentsView()
                self.checkScheduledTasks()
            } catch {
                self.showTaskAlert("Update failed", error.localizedDescription)
            }
        }
    }

    @objc private func toggleAgentEnabledClicked(_ sender: Any?) {
        let tasks = loadLocalTasks()
        guard !tasks.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "Enable/Disable task (auto-run)"
        alert.informativeText = "Disabled scheduled tasks do not run automatically."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        field.placeholderString = "Task #"
        alert.accessoryView = field
        alert.addButton(withTitle: "Toggle")
        alert.addButton(withTitle: "Cancel")
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            guard let n = Int(field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
                  n >= 1, n <= tasks.count else { return }
            let task = tasks[n-1]
            guard let filename = task["filename"] as? String else { return }
            let fileURL = self.localTasksDirectory().appendingPathComponent(filename)
            guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
            let currentlyEnabled = (task["enabled"] as? Bool) ?? ((self.parseFrontmatter(content)["enabled"] ?? "true").lowercased() != "false")
            content = self.updateFrontmatter(content, key: "enabled", value: !currentlyEnabled ? "true" : "false")
            try? content.write(to: fileURL, atomically: true, encoding: .utf8)
            self.fetchTasks()
            self.refreshAgentsView()
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
            let nextRunAt = parseNextRunDate(t["next_run_raw"] as? String)
            if isTaskDue(schedule: sched, id: id, now: now, nextRunAt: nextRunAt) {
                lastAutoRun[id] = now
                appendLog("[scheduler] Due: \(t["name"] as? String ?? id) (\(sched))")
                // Clear one-time next_run_at override after triggering; frequency continues via schedule.
                if let filename = t["filename"] as? String, nextRunAt != nil {
                    clearNextRunOverride(filename: filename)
                }
                runLocalTask(at: i)
            }
        }
    }

    private func clearNextRunOverride(filename: String) {
        let fileURL = localTasksDirectory().appendingPathComponent(filename)
        guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        content = updateFrontmatter(content, key: "next_run_at", value: "")
        try? content.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func isTaskDue(schedule: String, id: String, now: Date, nextRunAt: Date? = nil) -> Bool {
        if let last = lastAutoRun[id], now.timeIntervalSince(last) < 55 { return false }
        // Explicit next run time/date overrides: don't run before it; when reached, eligible.
        if let nr = nextRunAt {
            if now < nr { return false }
            return true
        }
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




    @objc private func editScheduleByIndex(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < currentTasks.count else { return }
        let task = currentTasks[idx]
        guard let filename = task["filename"] as? String else { return }
        let name = task["name"] as? String ?? filename
        let currentSched = (task["schedule"] as? String ?? "manual")
        let currentNext = (task["next_run_raw"] as? String) ?? ""
        let alert = NSAlert()
        alert.messageText = "Edit schedule: \(name)"
        alert.informativeText = "Set next run time/date (local) and how frequently it runs. Leave next run blank to use frequency only."
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 104))
        let freqLabel = NSTextField(labelWithString: "Frequency:")
        freqLabel.frame = NSRect(x: 0, y: 74, width: 76, height: 20)
        let freqField = NSTextField(frame: NSRect(x: 80, y: 72, width: 334, height: 24))
        freqField.stringValue = (currentSched == "-" ? "manual" : currentSched)
        freqField.placeholderString = "manual, @hourly, @daily, @every 30m, @every 1h, or 0 9 * * *"
        let nextLabel = NSTextField(labelWithString: "Next run:")
        nextLabel.frame = NSRect(x: 0, y: 42, width: 76, height: 20)
        let nextField = NSTextField(frame: NSRect(x: 80, y: 40, width: 334, height: 24))
        nextField.stringValue = (currentNext == "-" ? "" : currentNext)
        nextField.placeholderString = "yyyy-MM-dd HH:mm (local), or blank to clear"
        let hint = NSTextField(labelWithString: "Examples: 2026-11-06 09:00  |  @every 15m  |  @daily  |  manual")
        hint.frame = NSRect(x: 80, y: 12, width: 334, height: 20)
        hint.font = NSFont.systemFont(ofSize: 10)
        hint.textColor = .secondaryLabelColor
        container.addSubview(freqLabel); container.addSubview(freqField)
        container.addSubview(nextLabel); container.addSubview(nextField)
        container.addSubview(hint)
        alert.accessoryView = container
        alert.addButton(withTitle: "Save schedule")
        alert.addButton(withTitle: "Cancel")
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            let freq = freqField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let next = nextField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let fileURL = self.localTasksDirectory().appendingPathComponent(filename)
            guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
            if !freq.isEmpty {
                content = self.updateFrontmatter(content, key: "schedule", value: "\"\(freq)\"")
                if freq.lowercased() != "manual" {
                    content = self.updateFrontmatter(content, key: "enabled", value: "true")
                }
            }
            // store next run (blank clears)
            if next.isEmpty {
                content = self.updateFrontmatter(content, key: "next_run_at", value: "")
            } else {
                content = self.updateFrontmatter(content, key: "next_run_at", value: "\"\(next)\"")
                // if user sets a next run, ensure task is enabled unless explicitly manual intent? keep enabled state, but scheduling usually means enabled.
                if (freq.isEmpty ? currentSched : freq).lowercased() != "manual" {
                    content = self.updateFrontmatter(content, key: "enabled", value: "true")
                }
            }
            do {
                try content.write(to: fileURL, atomically: true, encoding: .utf8)
                self.appendLog("[scheduler] \(name): frequency=\(freq.isEmpty ? currentSched : freq), next_run=\(next.isEmpty ? "(cleared)" : next)")
                self.fetchTasks()
                self.refreshAgentsView()
                self.checkScheduledTasks()
            } catch {
                self.showTaskAlert("Schedule update failed", error.localizedDescription)
            }
        }
    }

    @objc private func toggleTaskEnabledByIndex(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < currentTasks.count else { return }
        let task = currentTasks[idx]
        guard let filename = task["filename"] as? String else { return }
        let fileURL = localTasksDirectory().appendingPathComponent(filename)
        guard var content = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        let currentlyEnabled = (task["enabled"] as? Bool) ?? ((parseFrontmatter(content)["enabled"] ?? "true").lowercased() != "false")
        let newValue = !currentlyEnabled
        content = updateFrontmatter(content, key: "enabled", value: newValue ? "true" : "false")
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            appendLog("[tasks] \(filename): enabled=\(newValue)")
            fetchTasks()
            refreshAgentsView()
        } catch {
            showTaskAlert("Update failed", error.localizedDescription)
        }
    }

    @objc private func renameTaskByIndex(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < currentTasks.count else { return }
        let task = currentTasks[idx]
        guard let filename = task["filename"] as? String else { return }
        let oldName = task["name"] as? String ?? filename
        let alert = NSAlert()
        alert.messageText = "Rename task"
        alert.informativeText = "Renames the task display name and local file (standalone)."
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = oldName
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            let rawName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawName.isEmpty else { return }
            let safe = rawName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "-")
            let newFilename = (safe.hasSuffix(".md") ? safe : safe + ".md")
            let dir = self.localTasksDirectory()
            let oldURL = dir.appendingPathComponent(filename)
            guard var content = try? String(contentsOf: oldURL, encoding: .utf8) else { return }
            content = self.updateFrontmatter(content, key: "name", value: rawName)
            content = self.updateFrontmatter(content, key: "id", value: safe)
            let newURL = dir.appendingPathComponent(newFilename)
            do {
                if oldURL.path != newURL.path, FileManager.default.fileExists(atPath: newURL.path) {
                    self.showTaskAlert("Rename failed", "A task named \(newFilename) already exists.")
                    return
                }
                try content.write(to: newURL, atomically: true, encoding: .utf8)
                if oldURL.path != newURL.path {
                    try? FileManager.default.removeItem(at: oldURL)
                }
                self.appendLog("[tasks] Renamed \(filename) → \(newFilename)")
                self.fetchTasks()
                self.refreshAgentsView()
                self.fetchResultsTasks()
            } catch {
                self.showTaskAlert("Rename failed", error.localizedDescription)
            }
        }
    }

    private func updateFrontmatter(_ content: String, key: String, value: String) -> String {
        let lines = content.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return content }
        var out: [String] = []
        var inFM = false
        var fmEnded = false
        var replaced = false
        for (i, line) in lines.enumerated() {
            if i == 0 && line.trimmingCharacters(in: .whitespaces) == "---" {
                inFM = true; out.append(line); continue
            }
            if inFM && !fmEnded && line.trimmingCharacters(in: .whitespaces) == "---" {
                if !replaced { out.append("\(key): \(value)") }
                inFM = false; fmEnded = true; out.append(line); continue
            }
            if inFM && !fmEnded {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("\(key):") {
                    out.append("\(key): \(value)")
                    replaced = true
                    continue
                }
            }
            out.append(line)
        }
        if !fmEnded { return content }
        return out.joined(separator: "\n")
    }

    @objc private func editTaskByIndex(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0, idx < currentTasks.count else { return }
        let task = currentTasks[idx]
        guard let filename = task["filename"] as? String else { return }
        let fileURL = localTasksDirectory().appendingPathComponent(filename)
        let content = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? (task["content"] as? String) ?? ""
        let fm = parseFrontmatter(content)
        let alert = NSAlert()
        alert.messageText = "Edit \(filename) (standalone)"
        alert.informativeText = "Edit content, schedule, next run, and enable/disable. Verify checks frontmatter; Save applies fields."
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 430))
        let fields = NSView(frame: NSRect(x: 0, y: 388, width: 560, height: 42))
        let enabledBox = NSButton(checkboxWithTitle: "Enabled (auto-run if scheduled)", target: nil, action: nil)
        enabledBox.frame = NSRect(x: 0, y: 22, width: 220, height: 18)
        enabledBox.state = ((fm["enabled"] ?? "true").lowercased() != "false") ? .on : .off
        let schedLabel = NSTextField(labelWithString: "Schedule:")
        schedLabel.frame = NSRect(x: 0, y: 0, width: 58, height: 18)
        let schedField = NSTextField(frame: NSRect(x: 60, y: -2, width: 170, height: 22))
        schedField.stringValue = fm["schedule"] ?? (task["schedule"] as? String ?? "manual")
        let nextLabel = NSTextField(labelWithString: "Next run:")
        nextLabel.frame = NSRect(x: 238, y: 0, width: 58, height: 18)
        let nextField = NSTextField(frame: NSRect(x: 298, y: -2, width: 170, height: 22))
        let nextRaw = fm["next_run_at"] ?? fm["next_run"] ?? ""
        nextField.stringValue = (nextRaw == "-" ? "" : nextRaw)
        nextField.placeholderString = "yyyy-MM-dd HH:mm or blank"
        fields.addSubview(enabledBox)
        fields.addSubview(schedLabel); fields.addSubview(schedField)
        fields.addSubview(nextLabel); fields.addSubview(nextField)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 40, width: 560, height: 340))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 560, height: 340))
        tv.string = content
        tv.isEditable = true
        tv.isRichText = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        if let c = tv.textContainer { c.widthTracksTextView = true }
        scroll.documentView = tv
        let verifyBtn = NSButton(title: "Verify", target: self, action: #selector(verifyTaskText(_:)))
        verifyBtn.bezelStyle = .rounded
        let saveBtn = NSButton(title: "Save", target: self, action: #selector(saveTaskText(_:)))
        saveBtn.bezelStyle = .rounded
        saveBtn.isHidden = true
        let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(cancelTaskEdit(_:)))
        cancelBtn.bezelStyle = .rounded
        let btnRow = NSStackView(views: [verifyBtn, saveBtn, cancelBtn])
        btnRow.orientation = .horizontal
        btnRow.spacing = 8
        btnRow.frame = NSRect(x: 0, y: 8, width: 560, height: 24)
        btnRow.alignment = .centerY
        container.addSubview(fields)
        container.addSubview(scroll)
        container.addSubview(btnRow)
        alert.accessoryView = container
        self.pendingEditFilename = filename
        self.pendingEditTextView = tv
        self.pendingEditSaveButton = saveBtn
        self.pendingEditScheduleField = schedField
        self.pendingEditNextRunField = nextField
        self.pendingEditEnabledBox = enabledBox
        guard let window = self.window else { return }
        alert.beginSheetModal(for: window) { [weak self] _ in _ = self }
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
        let win = self.window ?? NSApp.keyWindow
        let nameAlert = NSAlert()
        nameAlert.messageText = "New local task"
        nameAlert.informativeText = "Enter a task name, then add details."
        let nameField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        nameField.placeholderString = "my-task"
        nameAlert.accessoryView = nameField
        nameAlert.addButton(withTitle: "Next")
        nameAlert.addButton(withTitle: "Cancel")
        let handleName: (NSApplication.ModalResponse) -> Void = { [weak self] resp in
            guard let self, resp == .alertFirstButtonReturn else { return }
            let rawName = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawName.isEmpty else { return }
            let safe = rawName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "-")
            let template = """
            ---
            id: \(safe)
            name: \(rawName)
            schedule: "manual"
            enabled: true
            model: granite4:3b
            ---

            Describe what this task should do. When run, this text is sent to the local Ollama model as the workflow prompt.
            """
            let detail = NSAlert()
            detail.messageText = "Task details: \(rawName)"
            detail.informativeText = "Edit details, then Verify (checks frontmatter) and Save."
            let container = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 360))
            let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
            scroll.hasVerticalScroller = true
            scroll.borderType = .bezelBorder
            let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 520, height: 320))
            tv.isEditable = true
            tv.isRichText = false
            tv.isVerticallyResizable = true
            tv.autoresizingMask = [.width]
            tv.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            tv.string = template
            if let c = tv.textContainer { c.widthTracksTextView = true }
            scroll.documentView = tv
            let verifyBtn = NSButton(title: "Verify", target: self, action: #selector(self.verifyTaskText(_:)))
            verifyBtn.bezelStyle = .rounded
            let saveBtn = NSButton(title: "Save", target: self, action: #selector(self.saveTaskText(_:)))
            saveBtn.bezelStyle = .rounded
            saveBtn.isHidden = true
            let cancelBtn = NSButton(title: "Cancel", target: self, action: #selector(self.cancelTaskEdit(_:)))
            cancelBtn.bezelStyle = .rounded
            let btnRow = NSStackView(views: [verifyBtn, saveBtn, cancelBtn])
            btnRow.orientation = .horizontal
            btnRow.spacing = 8
            btnRow.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(scroll)
            container.addSubview(btnRow)
            NSLayoutConstraint.activate([
                btnRow.topAnchor.constraint(equalTo: container.topAnchor, constant: 0),
                btnRow.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                scroll.topAnchor.constraint(equalTo: btnRow.bottomAnchor, constant: 8),
                scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
            detail.accessoryView = container
            // New task: filename derived from verified/saved content (or prefill suggestion).
            self.pendingEditFilename = safe.hasSuffix(".md") ? safe : safe + ".md"
            self.pendingEditTextView = tv
            self.pendingEditSaveButton = saveBtn
            let win2 = self.window ?? NSApp.keyWindow
            if let win2 { detail.beginSheetModal(for: win2) { _ in } }
            else { detail.runModal() }
        }
        if let win { nameAlert.beginSheetModal(for: win, completionHandler: handleName) }
        else { handleName(nameAlert.runModal()) }
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
        seedDefaultTasksIfNeeded(into: base)
        return base
    }

    private func seedDefaultTasksIfNeeded(into tasksDir: URL) {
        let fm = FileManager.default
        let marker = tasksDir.appendingPathComponent(".feathera_defaults_seeded")
        if fm.fileExists(atPath: marker.path) { return }
        // First run: copy bundled default agent tasks. Users can delete any later.
        guard let defaultsDir = resolveBundledDefaultTasksDir() else {
            // Don't mark seeded if bundle missing (dev edge case) — try again next time.
            return
        }
        let files = (try? fm.contentsOfDirectory(at: defaultsDir, includingPropertiesForKeys: nil)) ?? []
        for src in files where src.pathExtension == "md" {
            let dst = tasksDir.appendingPathComponent(src.lastPathComponent)
            if !fm.fileExists(atPath: dst.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }
        try? Data("seeded".utf8).write(to: marker)
    }

    private func resolveBundledDefaultTasksDir() -> URL? {
        let fm = FileManager.default
        if let res = Bundle.main.resourceURL {
            let bundled = res.appendingPathComponent("DefaultTasks")
            if fm.fileExists(atPath: bundled.path) { return bundled }
        }
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let dev = repo.appendingPathComponent("Resources/DefaultTasks")
        if fm.fileExists(atPath: dev.path) { return dev }
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let rel = cwd.appendingPathComponent("Resources/DefaultTasks")
        if fm.fileExists(atPath: rel.path) { return rel }
        return nil
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
            let nextRunRaw = fmatter["next_run_at"] ?? fmatter["next_run"] ?? "-"
            var status = "idle"
            if runningTaskIDs.contains(id) {
                status = "running"
            } else if let last = loadLastLocalRun(taskId: id), let s = last["status"] as? String, !s.isEmpty {
                status = s // success / failed from last run
            }
            tasks.append([
                "number": i + 1,
                "id": id,
                "name": name,
                "filename": filename,
                "schedule": schedule,
                "enabled": enabled,
                "status": status,
                "last_model": model,
                "model": model,
                "next_run": formatNextRun(nextRunRaw),
                "next_run_raw": nextRunRaw,
                "content": content,
            ])
        }
        return tasks
    }

    private func loadLastLocalRun(taskId: String) -> [String: Any]? {
        let safe = taskId.replacingOccurrences(of: "/", with: "-")
        let url = localRunsDirectory().appendingPathComponent("\(safe).last.json")
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj
    }

    private func parseNextRunDate(_ raw: String?) -> Date? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw != "-" else { return nil }
        let iso = ISO8601DateFormatter()
        if let d = iso.date(from: raw) { return d }
        let fmts = ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "MM/dd/yyyy HH:mm", "yyyy-MM-dd"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: raw) { return d }
        }
        return nil
    }

    private func formatNextRun(_ raw: String?) -> String {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty, raw != "-" else { return "-" }
        if let d = parseNextRunDate(raw) {
            let df = DateFormatter()
            df.dateStyle = .short
            df.timeStyle = .short
            return df.string(from: d)
        }
        return raw
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
        alert.informativeText = "Choose a backup to restore. Task files will be restored locally (standalone; backups are not shown as tasks)."
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
        // Standalone: show last local run for this task (no external run history service).
        runPicker.removeAllItems()
        runPicker.menu?.appearance = NSAppearance(named: .darkAqua)
        if let last = loadLastLocalRun(taskId: taskId) {
            currentRuns = [last]
            let started = last["started_at"] as? String ?? "last run"
            let status = last["status"] as? String ?? "?"
            runPicker.addItem(withTitle: "\(started) [\(status)]")
            runPicker.selectItem(at: 0)
            showLocalRunResult(last)
        } else {
            currentRuns = []
            runPicker.addItem(withTitle: "(no runs yet)")
            let name = currentTasksForResults.first(where: { ($0["id"] as? String) == taskId })?["name"] as? String ?? taskId
            resultsTextView.string = "Task: \(name)\nNo local runs yet. Use Run in the Tasks tab."
        }
    }

    private func showLocalRunResult(_ run: [String: Any]) {
        let name = run["task_name"] as? String ?? (run["task_id"] as? String ?? "?")
        let status = run["status"] as? String ?? "?"
        let model = run["model"] as? String ?? "?"
        let started = run["started_at"] as? String ?? ""
        let output = run["output"] as? String ?? ""
        let err = run["error"] as? String ?? ""
        var header = ["Task: \(name)", "Status: \(status)", "Model: \(model)"]
        if !started.isEmpty { header.append("Started: \(started)") }
        if !err.isEmpty { header.append("Error: \(err)") }
        let body = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (err.isEmpty ? "(no output)" : "") : output
        resultsTextView.string = (header + ["", body]).joined(separator: "\n")
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
        // Standalone: show current local tasks only (new appear, deleted disappear). Backups are not shown.
        let tasks = loadLocalTasks()
        currentTasksForResults = tasks
        taskPicker.removeAllItems()
        taskPicker.menu?.appearance = NSAppearance(named: .darkAqua)
        for (i, t) in tasks.enumerated() {
            taskPicker.addItem(withTitle: "\(i+1). \(t["name"] as? String ?? "?")")
        }
        runPicker.removeAllItems()
        runPicker.menu?.appearance = NSAppearance(named: .darkAqua)
        if tasks.isEmpty {
            resultsTextView.string = "No local tasks. Add a task in the Tasks tab.\n(Backups are stored separately and not shown here.)"
            return
        }
        if let tid = currentResultTaskId, let idx = tasks.firstIndex(where: { ($0["id"] as? String) == tid }) {
            taskPicker.selectItem(at: idx)
            loadRunsForTask(taskId: tid)
        } else if let first = tasks.first, let tid = first["id"] as? String {
            taskPicker.selectItem(at: 0)
            currentResultTaskId = tid
            loadRunsForTask(taskId: tid)
        }
    }

    private func fetchLatestResult(taskId: String) {
        // Standalone: show latest local run for a task and switch to Results tab.
        currentResultTaskId = taskId
        fetchResultsTasks()
        loadRunsForTask(taskId: taskId)
        if let r = tabLabels.firstIndex(of: "Results") {
            tabControl.selectedSegment = r
            tabChanged(tabControl)
        }
    }

    private func loadResult(runId: Int) {
        // Standalone: show the selected local run from currentRuns (if present).
        if let r = currentRuns.first(where: { ($0["run_id"] as? Int) == runId }) ?? currentRuns.first {
            showLocalRunResult(r)
        }
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
        guard let tv = pendingEditTextView else { return }
        var newContent = tv.string
        // Apply schedule/next_run/enabled from Edit dialog fields (if present).
        if let sched = pendingEditScheduleField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), !sched.isEmpty {
            newContent = updateFrontmatter(newContent, key: "schedule", value: "\"\(sched)\"")
        }
        if let next = pendingEditNextRunField?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) {
            newContent = updateFrontmatter(newContent, key: "next_run_at", value: next.isEmpty ? "" : "\"\(next)\"")
        }
        if let enabledBox = pendingEditEnabledBox {
            newContent = updateFrontmatter(newContent, key: "enabled", value: enabledBox.state == .on ? "true" : "false")
        }
        // Standalone: save locally (no external scheduler). Filename may be set for edit or new task.
        var filename = pendingEditFilename?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if filename.isEmpty {
            let fm = parseFrontmatter(newContent)
            let base = (fm["id"] ?? fm["name"] ?? "task-\(Int(Date().timeIntervalSince1970))")
                .replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").replacingOccurrences(of: " ", with: "-")
            filename = base.hasSuffix(".md") ? base : base + ".md"
        }
        let fileURL = localTasksDirectory().appendingPathComponent(filename)
        do {
            try newContent.write(to: fileURL, atomically: true, encoding: .utf8)
            appendLog("[tasks] Saved \(filename)")
            fetchTasks()
            refreshAgentsView()
            checkScheduledTasks()
        } catch {
            showTaskAlert("Save failed", "Could not save \(filename): \(error.localizedDescription)")
        }
        if let window = self.window, let sheet = window.attachedSheet {
            window.endSheet(sheet)
        }
        pendingEditFilename = nil
        pendingEditTextView = nil
        pendingEditSaveButton = nil
        pendingEditScheduleField = nil
        pendingEditNextRunField = nil
        pendingEditEnabledBox = nil
    }

    @objc private func cancelTaskEdit(_ sender: Any?) {
        pendingEditFilename = nil
        pendingEditTextView = nil
        pendingEditSaveButton = nil
        pendingEditScheduleField = nil
        pendingEditNextRunField = nil
        pendingEditEnabledBox = nil
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

extension LocalChatView {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == ResearchBridge.handlerName {
            ResearchBridge.handle(message)
        }
    }
}

/// A vertically-flipped NSStackView so its content pins to the top of a scroll view.
final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}


private var ResearchPopupHelperKey: UInt8 = 0
@MainActor
final class ResearchPopupHelper: NSObject {
    private let onShow: () -> Void
    private let onClose: () -> Void
    init(onShow: @escaping () -> Void, onClose: @escaping () -> Void) { self.onShow = onShow; self.onClose = onClose }
    @objc func show(_ sender: Any?) { onShow() }
    @objc func close(_ sender: Any?) { onClose() }
}
