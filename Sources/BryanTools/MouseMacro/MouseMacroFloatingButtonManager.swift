import AppKit
import BryanToolsShared
import Foundation

@MainActor
final class MouseMacroFloatingButtonManager {
    static let buttonSize = NSSize(width: 57, height: 57)

    private let onTrigger: (UUID) -> Void
    private let onPositionChange: (UUID, MouseMacroFloatingButtonPosition) -> Void
    private var panels: [UUID: MouseMacroFloatingButtonPanel] = [:]

    init(
        onTrigger: @escaping (UUID) -> Void,
        onPositionChange: @escaping (UUID, MouseMacroFloatingButtonPosition) -> Void
    ) {
        self.onTrigger = onTrigger
        self.onPositionChange = onPositionChange
    }

    func sync(mappings: [MouseMacroMapping]) {
        let visibleMappings = mappings.filter(\.floatingButton.isVisible)
        let visibleIDs = Set(visibleMappings.map(\.id))

        let hiddenIDs = panels.keys.filter { !visibleIDs.contains($0) }
        for id in hiddenIDs {
            panels.removeValue(forKey: id)?.orderOut(nil)
        }

        for (index, mapping) in visibleMappings.enumerated() {
            let panel: MouseMacroFloatingButtonPanel
            if let existingPanel = panels[mapping.id] {
                panel = existingPanel
                panel.updateEmoji(mapping.floatingButton.emoji)
            } else {
                panel = MouseMacroFloatingButtonPanel(
                    emoji: mapping.floatingButton.emoji,
                    onTrigger: { [weak self] in
                        self?.onTrigger(mapping.id)
                    }
                )
                panel.onDragEnded = { [weak self, weak panel] in
                    guard let self, let panel else {
                        return
                    }
                    let origin = self.clampedOrigin(panel.frame.origin)
                    panel.setFrameOrigin(origin)
                    self.onPositionChange(
                        mapping.id,
                        MouseMacroFloatingButtonPosition(x: origin.x, y: origin.y)
                    )
                }
                panels[mapping.id] = panel
            }

            let requestedOrigin = mapping.floatingButton.position.map {
                NSPoint(x: $0.x, y: $0.y)
            } ?? defaultOrigin(index: index)
            panel.setFrameOrigin(clampedOrigin(requestedOrigin))
            panel.orderFrontRegardless()
        }
    }

    func closeAll() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func defaultOrigin(index: Int) -> NSPoint {
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            return NSPoint(x: 40, y: 40 + CGFloat(index) * 67)
        }

        let margin = CGFloat(20)
        let spacing = CGFloat(10)
        let step = Self.buttonSize.height + spacing
        let availableHeight = max(step, screenFrame.height - margin * 2)
        let buttonsPerColumn = max(1, Int(availableHeight / step))
        let row = index % buttonsPerColumn
        let column = index / buttonsPerColumn

        return NSPoint(
            x: screenFrame.maxX - margin - Self.buttonSize.width - CGFloat(column) * step,
            y: screenFrame.minY + margin + CGFloat(row) * step
        )
    }

    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return origin
        }

        let proposedFrame = NSRect(origin: origin, size: Self.buttonSize)
        let intersectingScreen = screens.max { left, right in
            intersectionArea(proposedFrame, left.visibleFrame) < intersectionArea(proposedFrame, right.visibleFrame)
        }
        let screen: NSScreen
        if let intersectingScreen,
           intersectionArea(proposedFrame, intersectingScreen.visibleFrame) > 0 {
            screen = intersectingScreen
        } else {
            screen = NSScreen.main ?? screens[0]
        }
        let frame = screen.visibleFrame
        let margin = CGFloat(6)

        return NSPoint(
            x: min(max(origin.x, frame.minX + margin), frame.maxX - Self.buttonSize.width - margin),
            y: min(max(origin.y, frame.minY + margin), frame.maxY - Self.buttonSize.height - margin)
        )
    }

    private func intersectionArea(_ left: NSRect, _ right: NSRect) -> CGFloat {
        let intersection = left.intersection(right)
        guard !intersection.isNull else {
            return 0
        }
        return intersection.width * intersection.height
    }
}

private final class MouseMacroFloatingButtonPanel: NSPanel {
    private let buttonView: MouseMacroFloatingButtonView
    var onDragEnded: (() -> Void)? {
        didSet {
            buttonView.onDragEnded = onDragEnded
        }
    }

    init(emoji: String, onTrigger: @escaping () -> Void) {
        buttonView = MouseMacroFloatingButtonView(emoji: emoji)
        super.init(
            contentRect: NSRect(origin: .zero, size: MouseMacroFloatingButtonManager.buttonSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        buttonView.onTrigger = onTrigger
        contentView = buttonView
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }

    func updateEmoji(_ emoji: String) {
        buttonView.emoji = emoji
    }
}

private final class MouseMacroFloatingButtonView: NSView {
    var emoji: String {
        didSet {
            needsDisplay = true
        }
    }
    var onTrigger: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var initialMouseLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private var isDragging = false

    init(emoji: String) {
        self.emoji = emoji
        super.init(frame: NSRect(origin: .zero, size: MouseMacroFloatingButtonManager.buttonSize))
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let boxRect = bounds.insetBy(dx: 1, dy: 1)
        let box = NSBezierPath(roundedRect: boxRect, xRadius: 10, yRadius: 10)
        NSColor(calibratedWhite: 0.88, alpha: 0.97).setFill()
        box.fill()
        NSColor(calibratedWhite: 0.56, alpha: 0.55).setStroke()
        box.lineWidth = 1
        box.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 31),
            .foregroundColor: NSColor.labelColor
        ]
        let attributedEmoji = NSAttributedString(string: emoji, attributes: attributes)
        let emojiSize = attributedEmoji.size()
        attributedEmoji.draw(at: NSPoint(
            x: bounds.midX - emojiSize.width / 2,
            y: bounds.midY - emojiSize.height / 2
        ))
    }

    override func mouseDown(with event: NSEvent) {
        initialMouseLocation = NSEvent.mouseLocation
        initialWindowOrigin = window?.frame.origin
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let initialMouseLocation, let initialWindowOrigin else {
            return
        }
        let currentLocation = NSEvent.mouseLocation
        let deltaX = currentLocation.x - initialMouseLocation.x
        let deltaY = currentLocation.y - initialMouseLocation.y
        if !isDragging, hypot(deltaX, deltaY) >= 4 {
            isDragging = true
        }
        guard isDragging else {
            return
        }
        window.setFrameOrigin(NSPoint(
            x: initialWindowOrigin.x + deltaX,
            y: initialWindowOrigin.y + deltaY
        ))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            initialMouseLocation = nil
            initialWindowOrigin = nil
            isDragging = false
        }

        if isDragging {
            onDragEnded?()
        } else {
            onTrigger?()
        }
    }
}
