import AppKit
import WebKit

/// The slim bar under the bookmarks bar for Edit ▸ Find (⌘F). Return / ⌘G finds the next match,
/// ⇧Return / ⇧⌘G the previous one, Esc closes it. Matches are highlighted by WebKit itself.
final class FindBar: NSView, NSSearchFieldDelegate {
    /// The last search, shared by all tabs like Safari's.
    static var lastQuery = ""

    let field = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    var onClose: (() -> Void)?
    weak var webView: WKWebView?

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true

        field.placeholderString = "Find on page"
        field.delegate = self
        field.sendsSearchStringImmediately = true
        field.target = self
        field.action = #selector(queryChanged(_:))
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        let prev = button("chevron.up", "Previous match (⇧⌘G)", #selector(findPrevious(_:)))
        let next = button("chevron.down", "Next match (⌘G)", #selector(findNext(_:)))
        let done = NSButton(title: "Done", target: self, action: #selector(close(_:)))
        done.bezelStyle = .rounded
        done.controlSize = .small

        let stack = NSStackView(views: [field, prev, next, status, NSView(), done])
        stack.spacing = 6
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 10, bottom: 0, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        addSubview(line)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            field.widthAnchor.constraint(equalToConstant: 240),
            line.leadingAnchor.constraint(equalTo: leadingAnchor),
            line.trailingAnchor.constraint(equalTo: trailingAnchor),
            line.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    private func button(_ symbol: String, _ tip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tip)!,
                         target: self, action: action)
        b.isBordered = false
        b.toolTip = tip
        return b
    }

    /// Shows the last search, selected, ready to type over.
    func activate() {
        if field.stringValue.isEmpty { field.stringValue = Self.lastQuery }
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
        if !field.stringValue.isEmpty { find(backwards: false) }
    }

    @objc private func queryChanged(_ sender: Any?) {
        Self.lastQuery = field.stringValue
        find(backwards: false)
    }

    @objc func findNext(_ sender: Any?) { find(backwards: false) }
    @objc func findPrevious(_ sender: Any?) { find(backwards: true) }
    @objc private func close(_ sender: Any?) { onClose?() }

    func find(backwards: Bool) {
        if field.stringValue.isEmpty { field.stringValue = Self.lastQuery }
        let query = field.stringValue
        guard !query.isEmpty, let webView else {
            status.stringValue = ""
            return
        }
        let config = WKFindConfiguration()
        config.backwards = backwards
        config.caseSensitive = false
        config.wraps = true
        webView.find(query, configuration: config) { [weak self] result in
            guard let self, self.field.stringValue == query else { return }
            self.status.stringValue = result.matchFound ? "" : "Not found"
            self.status.textColor = result.matchFound ? .secondaryLabelColor : .systemRed
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            find(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) == true)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            onClose?()
            return true
        default:
            return false
        }
    }
}
