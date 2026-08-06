import AppKit
import BryanToolsShared
import SwiftUI

@MainActor
final class AlarmCountdownWindowManager {
    static let panelSize = NSSize(width: 128, height: 32)

    private let onClick: () -> Void
    private let onDismiss: () -> Void
    private let onPositionChange: (AlarmPanelPosition) -> Void
    private var panel: AlarmCountdownPanel?

    init(
        onClick: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onPositionChange: @escaping (AlarmPanelPosition) -> Void
    ) {
        self.onClick = onClick
        self.onDismiss = onDismiss
        self.onPositionChange = onPositionChange
    }

    func show(text: String, position: AlarmPanelPosition?) {
        if let panel {
            panel.updateText(text)
            panel.orderFrontRegardless()
            return
        }

        let panel = AlarmCountdownPanel(text: text, onClick: onClick, onDismiss: onDismiss)
        panel.onDragEnded = { [weak self, weak panel] in
            guard let self, let panel else {
                return
            }
            let origin = self.clampedOrigin(panel.frame.origin)
            panel.setFrameOrigin(origin)
            self.onPositionChange(AlarmPanelPosition(x: origin.x, y: origin.y))
        }
        let requestedOrigin = position.map { NSPoint(x: $0.x, y: $0.y) } ?? defaultOrigin()
        panel.setFrameOrigin(clampedOrigin(requestedOrigin))
        self.panel = panel
        panel.orderFrontRegardless()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func defaultOrigin() -> NSPoint {
        guard let frame = NSScreen.main?.visibleFrame else {
            return NSPoint(x: 100, y: 100)
        }
        return NSPoint(
            x: frame.midX - Self.panelSize.width / 2,
            y: frame.maxY - Self.panelSize.height - 10
        )
    }

    private func clampedOrigin(_ origin: NSPoint) -> NSPoint {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return origin
        }

        let proposedFrame = NSRect(origin: origin, size: Self.panelSize)
        let screen = screens.max { left, right in
            intersectionArea(proposedFrame, left.visibleFrame) < intersectionArea(proposedFrame, right.visibleFrame)
        }.flatMap { intersectionArea(proposedFrame, $0.visibleFrame) > 0 ? $0 : nil }
            ?? NSScreen.main
            ?? screens[0]
        let frame = screen.visibleFrame
        let margin = CGFloat(6)

        return NSPoint(
            x: min(max(origin.x, frame.minX + margin), frame.maxX - Self.panelSize.width - margin),
            y: min(max(origin.y, frame.minY + margin), frame.maxY - Self.panelSize.height - margin)
        )
    }

    private func intersectionArea(_ left: NSRect, _ right: NSRect) -> CGFloat {
        let intersection = left.intersection(right)
        return intersection.isNull ? 0 : intersection.width * intersection.height
    }
}

private final class AlarmCountdownPanel: NSPanel {
    private let countdownView: AlarmCountdownView

    var onDragEnded: (() -> Void)? {
        didSet {
            countdownView.onDragEnded = onDragEnded
        }
    }

    init(text: String, onClick: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        countdownView = AlarmCountdownView(text: text)
        super.init(
            contentRect: NSRect(origin: .zero, size: AlarmCountdownWindowManager.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        countdownView.onClick = onClick
        countdownView.onDismiss = onDismiss
        contentView = countdownView
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

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func updateText(_ text: String) {
        countdownView.text = text
    }
}

private final class AlarmCountdownView: NSView {
    var text: String {
        didSet {
            needsDisplay = true
        }
    }
    var onClick: (() -> Void)?
    var onDismiss: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var initialMouseLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private var isDragging = false

    init(text: String) {
        self.text = text
        super.init(frame: NSRect(origin: .zero, size: AlarmCountdownWindowManager.panelSize))
        toolTip = "Click to manage alarm. Drag to move."
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8)
        NSColor.controlBackgroundColor.withAlphaComponent(0.97).setFill()
        box.fill()
        NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        box.lineWidth = 1
        box.stroke()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 14, weight: .semibold),
            .foregroundColor: NSColor.labelColor
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let timerArea = NSRect(x: 0, y: 0, width: bounds.width - 28, height: bounds.height)
        string.draw(at: NSPoint(x: timerArea.midX - size.width / 2, y: bounds.midY - size.height / 2))

        let xPath = NSBezierPath()
        let xBounds = NSRect(x: bounds.maxX - 20, y: bounds.midY - 5, width: 10, height: 10)
        xPath.move(to: NSPoint(x: xBounds.minX, y: xBounds.minY))
        xPath.line(to: NSPoint(x: xBounds.maxX, y: xBounds.maxY))
        xPath.move(to: NSPoint(x: xBounds.maxX, y: xBounds.minY))
        xPath.line(to: NSPoint(x: xBounds.minX, y: xBounds.maxY))
        NSColor.secondaryLabelColor.setStroke()
        xPath.lineWidth = 1.5
        xPath.stroke()
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
        let location = NSEvent.mouseLocation
        let deltaX = location.x - initialMouseLocation.x
        let deltaY = location.y - initialMouseLocation.y
        if !isDragging, hypot(deltaX, deltaY) >= 4 {
            isDragging = true
        }
        guard isDragging else {
            return
        }
        window.setFrameOrigin(NSPoint(x: initialWindowOrigin.x + deltaX, y: initialWindowOrigin.y + deltaY))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            initialMouseLocation = nil
            initialWindowOrigin = nil
            isDragging = false
        }
        let location = convert(event.locationInWindow, from: nil)
        if isDragging {
            onDragEnded?()
        } else if closeButtonRect.contains(location) {
            onDismiss?()
        } else {
            onClick?()
        }
    }

    private var closeButtonRect: NSRect {
        NSRect(x: bounds.maxX - 28, y: 0, width: 28, height: bounds.height)
    }
}

@MainActor
final class AlarmAlertWindowManager {
    private var panel: AlarmAlertPanel?

    func show(targetDate: Date, dismiss: @escaping () -> Void) {
        close()
        let panel = AlarmAlertPanel(targetDate: targetDate, dismiss: dismiss)
        self.panel = panel
        panel.show()
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}

private final class AlarmAlertPanel: NSPanel {
    private static let panelSize = NSSize(width: 300, height: 180)

    init(targetDate: Date, dismiss: @escaping () -> Void) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        contentView = NSHostingView(rootView: AlarmAlertView(targetDate: targetDate, dismiss: dismiss))
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show() {
        if let frame = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(
                x: frame.midX - Self.panelSize.width / 2,
                y: frame.maxY - Self.panelSize.height - 24
            ))
        } else {
            center()
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
    }
}

private struct AlarmAlertView: View {
    let targetDate: Date
    let dismiss: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "alarm.fill")
                .font(.system(size: 25, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            Text("Alarm")
                .font(.system(size: 20, weight: .semibold))

            Text("Scheduled for \(AlarmSchedule.timeTitle(for: targetDate))")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Dismiss", action: dismiss)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .frame(width: 300, height: 180)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.25))
        }
    }
}
