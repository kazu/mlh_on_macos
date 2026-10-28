import Cocoa

/// A small borderless, non-activating panel that lists conversion candidates
/// vertically ("1 日本語", ...), up to `pageSize` per page.
final class CandidatePanel: NSPanel {
    static let shared = CandidatePanel()
    static let pageSize = 9

    private let listView = CandidateListView()
    private let effectView = NSVisualEffectView()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 100, height: 30),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: true)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]

        effectView.material = .menu
        effectView.state = .active
        effectView.blendingMode = .behindWindow
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 6
        effectView.layer?.masksToBounds = true
        effectView.autoresizingMask = [.width, .height]
        listView.autoresizingMask = [.width, .height]
        effectView.addSubview(listView)
        contentView = effectView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Page (0-based) containing `index`.
    static func page(of index: Int) -> Int { max(0, index) / pageSize }

    /// Shows `candidates` with `selected` highlighted, just below `anchor`
    /// (the line rectangle of the marked text, in screen coordinates).
    func show(candidates: [String], selected: Int, anchor: NSRect) {
        guard !candidates.isEmpty else { hide(); return }
        let page = Self.page(of: selected)
        let pageCount = (candidates.count + Self.pageSize - 1) / Self.pageSize
        let start = page * Self.pageSize
        let items = Array(candidates[start..<min(start + Self.pageSize, candidates.count)])
        listView.configure(items: items,
                           selected: selected - start,
                           pageLabel: pageCount > 1 ? "\(page + 1)/\(pageCount)" : nil)
        let size = listView.fittingSize
        let frame = Self.place(size: size, anchor: anchor)
        setFrame(frame, display: true)
        listView.frame = NSRect(origin: .zero, size: size)
        listView.needsDisplay = true
        orderFrontRegardless()
    }

    func hide() {
        if isVisible { orderOut(nil) }
    }

    private static func place(size: NSSize, anchor: NSRect) -> NSRect {
        let gap: CGFloat = 4
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor.origin) })
            ?? NSScreen.screens.first(where: { $0.frame.intersects(anchor) })
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var origin = NSPoint(x: anchor.minX, y: anchor.minY - gap - size.height)
        if origin.y < visible.minY {
            // No room below: flip above the line.
            origin.y = anchor.maxY + gap
        }
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        return NSRect(origin: origin, size: size)
    }
}

/// Draws the candidate rows. Uses dynamic system colors so it follows the
/// light/dark appearance.
private final class CandidateListView: NSView {
    private var items: [String] = []
    private var selected = 0
    private var pageLabel: String?

    private let padding = NSEdgeInsets(top: 4, left: 4, bottom: 4, right: 4)
    private let rowHPadding: CGFloat = 6
    private let rowVPadding: CGFloat = 2
    private let numberGap: CGFloat = 8
    private let textFont = NSFont.systemFont(ofSize: 15)
    private let numberFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    private let pageFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)

    override var isFlipped: Bool { true }

    func configure(items: [String], selected: Int, pageLabel: String?) {
        self.items = items
        self.selected = selected
        self.pageLabel = pageLabel
        invalidateIntrinsicContentSize()
    }

    private var rowHeight: CGFloat {
        ceil(max(textFont.ascender - textFont.descender + textFont.leading, 18)) + rowVPadding * 2
    }

    private var numberWidth: CGFloat {
        ceil(("9" as NSString).size(withAttributes: [.font: numberFont]).width)
    }

    private var pageLabelHeight: CGFloat {
        pageLabel == nil ? 0 : ceil(pageFont.ascender - pageFont.descender) + 2
    }

    override var fittingSize: NSSize {
        var width: CGFloat = 0
        for item in items {
            width = max(width, ceil((item as NSString).size(withAttributes: [.font: textFont]).width))
        }
        var total = padding.left + rowHPadding + numberWidth + numberGap + width + rowHPadding + padding.right
        if let label = pageLabel {
            let w = ceil((label as NSString).size(withAttributes: [.font: pageFont]).width)
            total = max(total, padding.left + w + rowHPadding * 2 + padding.right)
        }
        total = max(total, 80)
        let height = padding.top + rowHeight * CGFloat(items.count) + pageLabelHeight + padding.bottom
        return NSSize(width: total, height: height)
    }

    override var intrinsicContentSize: NSSize { fittingSize }

    override func draw(_ dirtyRect: NSRect) {
        let rowWidth = bounds.width - padding.left - padding.right
        for (i, item) in items.enumerated() {
            let rowRect = NSRect(x: padding.left, y: padding.top + rowHeight * CGFloat(i),
                                 width: rowWidth, height: rowHeight)
            let isSelected = i == selected
            if isSelected {
                NSColor.selectedContentBackgroundColor.setFill()
                NSBezierPath(roundedRect: rowRect, xRadius: 4, yRadius: 4).fill()
            }
            let textColor: NSColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
            let numberColor: NSColor = isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor

            let number = "\(i + 1)" as NSString
            let numberAttrs: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: numberColor]
            let numberSize = number.size(withAttributes: numberAttrs)
            let textAttrs: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: textColor]
            let textSize = (item as NSString).size(withAttributes: textAttrs)

            let numberX = rowRect.minX + rowHPadding
            number.draw(at: NSPoint(x: numberX + numberWidth - numberSize.width,
                                    y: rowRect.midY - numberSize.height / 2),
                        withAttributes: numberAttrs)
            (item as NSString).draw(at: NSPoint(x: numberX + numberWidth + numberGap,
                                                y: rowRect.midY - textSize.height / 2),
                                    withAttributes: textAttrs)
        }
        if let label = pageLabel {
            let attrs: [NSAttributedString.Key: Any] = [.font: pageFont, .foregroundColor: NSColor.tertiaryLabelColor]
            let s = label as NSString
            let size = s.size(withAttributes: attrs)
            let y = padding.top + rowHeight * CGFloat(items.count) + 1
            s.draw(at: NSPoint(x: bounds.width - padding.right - rowHPadding - size.width, y: y),
                   withAttributes: attrs)
        }
    }
}
