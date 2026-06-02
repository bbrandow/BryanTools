import AppKit
import Foundation

@MainActor
final class ShotFloatWindowManager {
    static let shared = ShotFloatWindowManager()

    private var panels: [ShotFloatPanel] = []

    private init() {}

    func float(_ image: NSImage) {
        let panel = ShotFloatPanel(image: image) { [weak self] panel in
            self?.close(panel)
        }
        panels.append(panel)
        panel.show()
    }

    func closeAll() {
        for panel in panels {
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func close(_ panel: ShotFloatPanel) {
        panel.orderOut(nil)
        panels.removeAll { $0 === panel }
    }
}

private final class ShotFloatPanel: NSPanel {
    private let floatView: ShotFloatImageView

    init(image: NSImage, onClose: @escaping (ShotFloatPanel) -> Void) {
        let initialZoom = ShotFloatPanel.initialZoom(for: image)
        self.floatView = ShotFloatImageView(image: image, zoom: initialZoom)
        let contentSize = ShotFloatImageView.contentSize(for: image, zoom: initialZoom)

        super.init(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        floatView.onClose = { [weak self] in
            guard let self else {
                return
            }
            onClose(self)
        }
        floatView.onZoomChange = { [weak self] zoom in
            self?.resize(zoom: zoom)
        }

        contentView = floatView
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    func show() {
        if let screenFrame = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(
                x: screenFrame.midX - frame.width / 2,
                y: screenFrame.midY - frame.height / 2
            ))
        } else {
            center()
        }
        orderFrontRegardless()
        makeKey()
    }

    private func resize(zoom: CGFloat) {
        let oldFrame = frame
        let center = CGPoint(x: oldFrame.midX, y: oldFrame.midY)
        let size = ShotFloatImageView.contentSize(for: floatView.image, zoom: zoom)
        let newFrame = NSRect(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2,
            width: size.width,
            height: size.height
        )
        setFrame(newFrame, display: true, animate: false)
    }

    private static func initialZoom(for image: NSImage) -> CGFloat {
        let imageSize = ShotFloatImageView.validImageSize(image)
        guard let screenFrame = NSScreen.main?.visibleFrame else {
            return min(1, min(720 / imageSize.width, 520 / imageSize.height))
        }
        let maxWidth = min(820, screenFrame.width * 0.7)
        let maxHeight = min(620, screenFrame.height * 0.7)
        return min(1, max(0.18, min(maxWidth / imageSize.width, maxHeight / imageSize.height)))
    }
}

private final class ShotFloatImageView: NSView {
    static let topBarHeight = CGFloat(24)
    static let minimumImageDimension = CGFloat(120)
    static let maximumImageDimension = CGFloat(2_400)

    let image: NSImage
    var onClose: (() -> Void)?
    var onZoomChange: ((CGFloat) -> Void)?

    private var zoom: CGFloat

    init(image: NSImage, zoom: CGFloat) {
        self.image = image
        self.zoom = zoom
        super.init(frame: NSRect(origin: .zero, size: Self.contentSize(for: image, zoom: zoom)))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let imageRect = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.topBarHeight)
        let backgroundPath = NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6)
        NSColor.windowBackgroundColor.setFill()
        backgroundPath.fill()

        image.draw(in: imageRect, from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)

        let topBarRect = NSRect(x: 0, y: bounds.height - Self.topBarHeight, width: bounds.width, height: Self.topBarHeight)
        NSColor.windowBackgroundColor.withAlphaComponent(0.92).setFill()
        topBarRect.fill()
        NSColor.black.withAlphaComponent(0.16).setStroke()
        NSBezierPath(rect: NSRect(x: 0, y: topBarRect.minY, width: bounds.width, height: 1)).stroke()

        drawCloseButton()
    }

    override func mouseDown(with event: NSEvent) {
        if closeButtonRect.contains(convert(event.locationInWindow, from: nil)) {
            onClose?()
            return
        }
        window?.performDrag(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let direction = event.scrollingDeltaY == 0 ? -event.scrollingDeltaX : event.scrollingDeltaY
        guard direction != 0 else {
            return
        }
        let multiplier = direction > 0 ? CGFloat(1.08) : CGFloat(0.925)
        let imageSize = Self.validImageSize(image)
        let minZoom = Self.minimumImageDimension / max(imageSize.width, imageSize.height)
        let maxZoom = Self.maximumImageDimension / max(imageSize.width, imageSize.height)
        zoom = min(max(zoom * multiplier, minZoom), maxZoom)
        onZoomChange?(zoom)
        needsDisplay = true
    }

    static func contentSize(for image: NSImage, zoom: CGFloat) -> NSSize {
        let imageSize = validImageSize(image)
        return NSSize(
            width: max(1, imageSize.width * zoom),
            height: max(1, imageSize.height * zoom) + topBarHeight
        )
    }

    static func validImageSize(_ image: NSImage) -> NSSize {
        let size = image.size
        guard size.width > 0, size.height > 0 else {
            return NSSize(width: 320, height: 240)
        }
        return size
    }

    private var closeButtonRect: NSRect {
        NSRect(x: bounds.width - 22, y: bounds.height - 21, width: 18, height: 18)
    }

    private func drawCloseButton() {
        let rect = closeButtonRect
        let circle = NSBezierPath(ovalIn: rect)
        NSColor.black.withAlphaComponent(0.55).setFill()
        circle.fill()

        let path = NSBezierPath()
        path.move(to: CGPoint(x: rect.minX + 5, y: rect.minY + 5))
        path.line(to: CGPoint(x: rect.maxX - 5, y: rect.maxY - 5))
        path.move(to: CGPoint(x: rect.maxX - 5, y: rect.minY + 5))
        path.line(to: CGPoint(x: rect.minX + 5, y: rect.maxY - 5))
        NSColor.white.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
