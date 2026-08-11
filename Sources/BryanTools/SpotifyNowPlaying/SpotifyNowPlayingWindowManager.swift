import AppKit
import BryanToolsShared

@MainActor
final class SpotifyNowPlayingWindowManager {
    static let panelSize = NSSize(width: 300, height: 64)

    private let onDismiss: () -> Void
    private let onPositionChange: (SpotifyNowPlayingPosition) -> Void
    private var panel: SpotifyNowPlayingPanel?

    init(
        onDismiss: @escaping () -> Void,
        onPositionChange: @escaping (SpotifyNowPlayingPosition) -> Void
    ) {
        self.onDismiss = onDismiss
        self.onPositionChange = onPositionChange
    }

    func show(snapshot: SpotifyNowPlayingSnapshot, position: SpotifyNowPlayingPosition?) {
        if let panel {
            panel.update(snapshot: snapshot)
            panel.orderFrontRegardless()
            return
        }

        let panel = SpotifyNowPlayingPanel(snapshot: snapshot, onDismiss: onDismiss)
        panel.onDragEnded = { [weak self, weak panel] in
            guard let self, let panel else {
                return
            }
            let origin = self.clampedOrigin(panel.frame.origin)
            panel.setFrameOrigin(origin)
            self.onPositionChange(SpotifyNowPlayingPosition(x: origin.x, y: origin.y))
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
            x: frame.maxX - Self.panelSize.width - 20,
            y: frame.maxY - Self.panelSize.height - 20
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

private final class SpotifyNowPlayingPanel: NSPanel {
    private let nowPlayingView: SpotifyNowPlayingView

    var onDragEnded: (() -> Void)? {
        didSet {
            nowPlayingView.onDragEnded = onDragEnded
        }
    }

    init(snapshot: SpotifyNowPlayingSnapshot, onDismiss: @escaping () -> Void) {
        nowPlayingView = SpotifyNowPlayingView(snapshot: snapshot)
        super.init(
            contentRect: NSRect(origin: .zero, size: SpotifyNowPlayingWindowManager.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        nowPlayingView.onDismiss = onDismiss
        contentView = nowPlayingView
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

    func update(snapshot: SpotifyNowPlayingSnapshot) {
        nowPlayingView.snapshot = snapshot
    }
}

private final class SpotifyNowPlayingView: NSView {
    var snapshot: SpotifyNowPlayingSnapshot {
        didSet {
            needsDisplay = true
        }
    }
    var onDismiss: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var initialMouseLocation: NSPoint?
    private var initialWindowOrigin: NSPoint?
    private var isDragging = false

    init(snapshot: SpotifyNowPlayingSnapshot) {
        self.snapshot = snapshot
        super.init(frame: NSRect(origin: .zero, size: SpotifyNowPlayingWindowManager.panelSize))
        toolTip = "Spotify Now Playing. Drag to move or use X to hide."
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let box = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.withAlphaComponent(0.97).setFill()
        box.fill()
        NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        box.lineWidth = 1
        box.stroke()

        let iconRect = NSRect(x: 12, y: bounds.midY - 15, width: 30, height: 30)
        NSColor(calibratedRed: 0.12, green: 0.72, blue: 0.36, alpha: 1).setFill()
        NSBezierPath(ovalIn: iconRect).fill()
        drawMusicSymbol(in: iconRect)

        let textX = CGFloat(52)
        let textWidth = bounds.width - textX - 34
        drawText(
            SpotifyNowPlayingDisplay.primaryText(for: snapshot),
            in: NSRect(x: textX, y: 34, width: textWidth, height: 19),
            font: NSFont.systemFont(ofSize: 14, weight: .semibold),
            color: .labelColor
        )
        drawText(
            SpotifyNowPlayingDisplay.secondaryText(for: snapshot),
            in: NSRect(x: textX, y: 14, width: textWidth, height: 17),
            font: NSFont.systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        drawCloseButton()
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
        }
    }

    private func drawMusicSymbol(in rect: NSRect) {
        guard let image = NSImage(
            systemSymbolName: "music.note",
            accessibilityDescription: "Spotify"
        ) else {
            return
        }
        let pointConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let colorConfiguration = NSImage.SymbolConfiguration(hierarchicalColor: .white)
        let configuredImage = image.withSymbolConfiguration(pointConfiguration.applying(colorConfiguration)) ?? image
        let imageSize = configuredImage.size
        configuredImage.draw(in: NSRect(
            x: rect.midX - imageSize.width / 2,
            y: rect.midY - imageSize.height / 2,
            width: imageSize.width,
            height: imageSize.height
        ))
    }

    private func drawText(
        _ text: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(
            in: rect,
            withAttributes: [
                .font: font,
                .foregroundColor: color,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func drawCloseButton() {
        let xBounds = NSRect(x: bounds.maxX - 20, y: bounds.maxY - 20, width: 10, height: 10)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: xBounds.minX, y: xBounds.minY))
        path.line(to: NSPoint(x: xBounds.maxX, y: xBounds.maxY))
        path.move(to: NSPoint(x: xBounds.maxX, y: xBounds.minY))
        path.line(to: NSPoint(x: xBounds.minX, y: xBounds.maxY))
        NSColor.secondaryLabelColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    private var closeButtonRect: NSRect {
        NSRect(x: bounds.maxX - 30, y: bounds.maxY - 30, width: 30, height: 30)
    }
}
