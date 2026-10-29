import AppKit

/// Feather's tab strip, under the toolbar. Tabs keep a comfortable fixed width from the left
/// and shrink only when the window runs out of room; past that, the » button lists them all.
/// Pinned tabs are narrow and show only a site badge. A group's tabs sit together after a
/// label in the group's color, and each is underlined in that color.
final class TabStripView: NSView {
    static let height: CGFloat = 32
    static let tabWidth: CGFloat = 200
    static let minTabWidth: CGFloat = 72
    static let pinnedWidth: CGFloat = 36 // about 3–4 letters wide

    weak var owner: TabWindow?

    private enum Kind: Equatable { case label(UUID), tab(UUID) }
    private struct Slot { var kind: Kind; var rect: NSRect }
    private var slots: [Slot] = []
    private var plusRect = NSRect.zero
    private var overflowRect = NSRect.zero
    private var hovered: UUID?
    private var dragging: UUID?

    override var isFlipped: Bool { true }

    func reload() {
        computeSlots()
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        computeSlots()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self))
    }

    // MARK: Layout

    private var labelFont: NSFont { .systemFont(ofSize: 11, weight: .semibold) }
    private var titleFont: NSFont { .systemFont(ofSize: 12) }

    private func labelWidth(_ group: TabGroup) -> CGFloat {
        min(ceil((group.name as NSString).size(withAttributes: [.font: labelFont]).width) + 16, 120)
    }

    private func computeSlots() {
        slots = []
        guard let model = owner?.model else { return }
        let groups = Dictionary(TabGroups.shared.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let runs = model.runs
        let pinned = model.pinnedCount
        let unpinned = model.tabs.count - pinned
        let labels = runs.filter { !model.tabs[$0.range.lowerBound].pinned }.compactMap { $0.group.flatMap { groups[$0] } }
        let fixed = CGFloat(pinned) * Self.pinnedWidth + labels.reduce(0) { $0 + labelWidth($1) + 4 }
        let room = bounds.width - 8 - fixed - 64 // + and » buttons
        let width = unpinned == 0 ? Self.tabWidth
            : min(Self.tabWidth, max(Self.minTabWidth, floor(room / CGFloat(unpinned))))
        var x: CGFloat = 8
        let y: CGFloat = 4, h = Self.height - 6
        for run in runs {
            if let id = run.group, let group = groups[id], !model.tabs[run.range.lowerBound].pinned {
                let w = labelWidth(group)
                slots.append(Slot(kind: .label(id), rect: NSRect(x: x, y: y + 4, width: w, height: h - 8)))
                x += w + 4
            }
            for tab in model.tabs[run.range] {
                let w = tab.pinned ? Self.pinnedWidth : width
                slots.append(Slot(kind: .tab(tab.id), rect: NSRect(x: x, y: y, width: w, height: h)))
                x += w
            }
        }
        let overflow = x + 32 > bounds.width - 30
        overflowRect = overflow ? NSRect(x: bounds.width - 30, y: y, width: 26, height: h) : .zero
        plusRect = NSRect(x: min(x + 4, bounds.width - (overflow ? 58 : 32)), y: y, width: 26, height: h)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.blended(withFraction: 0.05, of: .black)?.setFill()
        bounds.fill()
        guard let owner else { return }
        let groups = Dictionary(TabGroups.shared.all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let selected = owner.model.selected
        let clipRight = overflowRect == .zero ? bounds.width : overflowRect.minX
        NSGraphicsContext.saveGraphicsState()
        NSRect(x: 0, y: 0, width: min(clipRight, plusRect.minX), height: bounds.height).clip()
        for (i, slot) in slots.enumerated() {
            switch slot.kind {
            case .label(let id):
                guard let group = groups[id] else { continue }
                drawLabel(group, in: slot.rect)
            case .tab(let id):
                guard let item = owner.model.tab(id), let tab = owner.tabs.first(where: { $0.tabID == id }) else { continue }
                let next = slots.indices.contains(i + 1) ? slots[i + 1].kind : nil
                drawTab(tab, item: item, in: slot.rect, selected: id == selected,
                        group: item.group.flatMap { groups[$0] }, separator: next != .tab(selected ?? UUID()) && id != selected)
            }
        }
        NSGraphicsContext.restoreGraphicsState()
        drawSymbol("plus", in: plusRect)
        if overflowRect != .zero { drawSymbol("chevron.right.2", in: overflowRect) }
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    private func drawLabel(_ group: TabGroup, in rect: NSRect) {
        group.color.nsColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        let text: NSColor = group.color == .yellow ? .black : .white
        draw(group.name, in: rect.insetBy(dx: 8, dy: 0), font: labelFont, color: text, centered: true)
    }

    private func drawTab(_ tab: BrowserWindowController, item: TabItem, in rect: NSRect, selected: Bool,
                         group: TabGroup?, separator: Bool) {
        let body = rect.insetBy(dx: 2, dy: 0)
        if selected {
            NSColor.controlBackgroundColor.setFill()
            NSBezierPath(roundedRect: body, xRadius: 7, yRadius: 7).fill()
        } else if hovered == item.id {
            NSColor.controlBackgroundColor.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: body, xRadius: 7, yRadius: 7).fill()
        } else if separator {
            NSColor.separatorColor.setFill()
            NSRect(x: rect.maxX - 0.5, y: rect.minY + 7, width: 1, height: rect.height - 14).fill()
        }
        if let group {
            group.color.nsColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: body.minX + 6, y: body.maxY - 3, width: body.width - 12, height: 3),
                         xRadius: 1.5, yRadius: 1.5).fill()
        }
        let badge = NSRect(x: item.pinned ? body.midX - 8 : body.minX + 8, y: body.midY - 8, width: 16, height: 16)
        drawBadge(for: tab, in: badge)
        guard !item.pinned else {
            if tab.isPlayingAudio || tab.isMuted {
                draw(tab.isMuted ? "🔇" : "🔊", in: NSRect(x: badge.maxX - 4, y: badge.minY - 6, width: 14, height: 12),
                     font: .systemFont(ofSize: 8), color: .labelColor, centered: false)
            }
            return
        }
        var titleRect = NSRect(x: badge.maxX + 6, y: body.minY, width: body.maxX - badge.maxX - 30, height: body.height)
        if tab.isPlayingAudio || tab.isMuted {
            draw(tab.isMuted ? "🔇" : "🔊", in: NSRect(x: titleRect.minX, y: body.minY, width: 18, height: body.height),
                 font: .systemFont(ofSize: 11), color: .labelColor, centered: false)
            titleRect.origin.x += 18
            titleRect.size.width -= 18
        }
        draw(tab.displayTitle, in: titleRect, font: titleFont,
             color: tab.isAsleep && !selected ? .secondaryLabelColor : .labelColor, centered: false)
        if selected || hovered == item.id {
            drawSymbol("xmark", in: closeRect(for: rect), size: 9)
        }
    }

    /// A rounded square with the site's first letter, tinted by the group color.
    private func drawBadge(for tab: BrowserWindowController, in rect: NSRect) {
        let group = tab.tabGroupID.flatMap { TabGroups.shared.group(id: $0) }
        (group?.color.nsColor ?? .systemGray).withAlphaComponent(group == nil ? 0.35 : 0.9).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
        let host = tab.siteHost.replacingOccurrences(of: "www.", with: "")
        let letter = host.first.map { String($0).uppercased() } ?? "•"
        draw(letter, in: rect, font: .systemFont(ofSize: 10, weight: .bold),
             color: group == nil || group?.color == .yellow ? .labelColor : .white, centered: true)
    }

    private func closeRect(for rect: NSRect) -> NSRect {
        NSRect(x: rect.maxX - 22, y: rect.midY - 8, width: 16, height: 16)
    }

    private func drawSymbol(_ name: String, in rect: NSRect, size: CGFloat = 12) {
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .medium)) else { return }
        let tinted = image.copy() as! NSImage
        tinted.lockFocus()
        NSColor.secondaryLabelColor.set()
        NSRect(origin: .zero, size: tinted.size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        let s = tinted.size
        tinted.draw(in: NSRect(x: rect.midX - s.width / 2, y: rect.midY - s.height / 2, width: s.width, height: s.height),
                    from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    private func draw(_ text: String, in rect: NSRect, font: NSFont, color: NSColor, centered: Bool) {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        style.alignment = centered ? .center : .left
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let h = ceil(font.ascender - font.descender)
        (text as NSString).draw(in: NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h), withAttributes: attrs)
    }

    // MARK: Mouse

    private func slot(at point: NSPoint) -> Slot? {
        slots.first { $0.rect.contains(point) && $0.rect.maxX <= (overflowRect == .zero ? bounds.width : overflowRect.minX) }
    }

    private func tab(_ id: UUID) -> BrowserWindowController? { owner?.tabs.first { $0.tabID == id } }

    /// Where a tab dropped at a screen point would go in this strip.
    func insertionIndex(atScreen point: NSPoint) -> Int {
        guard let window else { return .max }
        let x = convert(window.convertPoint(fromScreen: point), from: nil).x
        var index = 0
        for slot in slots {
            guard case .tab = slot.kind else { continue }
            if x < slot.rect.midX { return index }
            index += 1
        }
        return index
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        var id: UUID?
        if case .tab(let t)? = slot(at: point)?.kind { id = t }
        if id != hovered { hovered = id; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) {
        hovered = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        guard let owner else { return }
        let point = convert(event.locationInWindow, from: nil)
        if plusRect.contains(point) { owner.newWindowForTab(nil); return }
        if overflowRect.contains(point) { showOverflowMenu(); return }
        guard let slot = slot(at: point) else {
            if event.clickCount == 2 { owner.newWindowForTab(nil) }
            return
        }
        switch slot.kind {
        case .label(let id):
            NSMenu.popUpContextMenu(TabGroupsMenu.shared.groupMenu(for: id), with: event, for: self)
        case .tab(let id):
            guard let tab = tab(id) else { return }
            if !(owner.model.tab(id)?.pinned ?? true), closeRect(for: slot.rect).contains(point),
               owner.model.selected == id || hovered == id {
                owner.close(tab)
                return
            }
            owner.select(tab)
            track(tab, from: event)
        }
    }

    /// Drag to reorder; drag off the strip to move the tab to another window or a new one.
    private func track(_ tab: BrowserWindowController, from event: NSEvent) {
        guard let window, let owner else { return }
        let start = event.locationInWindow
        var moved = false
        var tornOff = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp], until: .distantFuture,
                                          inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { break }
            let p = next.locationInWindow
            if !moved, abs(p.x - start.x) < 5, abs(p.y - start.y) < 5 { continue }
            moved = true
            let local = convert(p, from: nil)
            tornOff = local.y < -24 || local.y > bounds.height + 24 || owner.model.tabs.count == 1
            if !tornOff {
                let index = insertionIndex(atScreen: window.convertPoint(toScreen: p))
                let current = owner.index(of: tab) ?? 0
                let target = index > current ? index - 1 : index
                if target != current { owner.move(tab, to: target) }
            }
            NSCursor.closedHand.set()
        }
        NSCursor.arrow.set()
        if moved, tornOff { owner.tearOff(tab, at: NSEvent.mouseLocation) }
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2, case .tab(let id)? = slot(at: convert(event.locationInWindow, from: nil))?.kind,
              let tab = tab(id) else { return super.otherMouseDown(with: event) }
        owner?.close(tab)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        switch slot(at: convert(event.locationInWindow, from: nil))?.kind {
        case .tab(let id)?: return tab(id)?.tabMenu()
        case .label(let id)?: return TabGroupsMenu.shared.groupMenu(for: id)
        case nil: return nil
        }
    }

    private func showOverflowMenu() {
        guard let owner else { return }
        let menu = NSMenu()
        for tab in owner.tabs {
            let item = ClosureMenuItem(title: tab.displayTitle.isEmpty ? "New Tab" : tab.displayTitle) { [weak owner] in
                owner?.select(tab)
            }
            item.state = tab === owner.selectedTab ? .on : .off
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: overflowRect.minX, y: overflowRect.maxY), in: self)
    }
}
