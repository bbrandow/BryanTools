import AppKit
import Foundation

@MainActor
final class ColorPickerOverlayController {
    private let captures: [ColorPickerScreenCapture]
    private let onPick: (ColorPickerSample) -> Void
    private let onCancel: () -> Void
    private var windows: [NSWindow] = []

    init(
        captures: [ColorPickerScreenCapture],
        onPick: @escaping (ColorPickerSample) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.captures = captures
        self.onPick = onPick
        self.onCancel = onCancel
    }

    func show() {
        close()
        windows = captures.map { capture in
            let view = ColorPickerOverlayView(
                capture: capture,
                onPick: onPick,
                onCancel: onCancel
            )
            let window = ColorPickerOverlayWindow(capture: capture, contentView: view)
            window.orderFrontRegardless()
            window.makeKey()
            return window
        }
        NSCursor.crosshair.set()
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        for window in windows {
            window.orderOut(nil)
            window.contentView = nil
        }
        windows.removeAll()
        NSCursor.arrow.set()
    }
}

private final class ColorPickerOverlayWindow: NSWindow {
    init(capture: ColorPickerScreenCapture, contentView: NSView) {
        super.init(
            contentRect: capture.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        setFrame(capture.frame, display: false)
        self.contentView = contentView
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        level = .screenSaver
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

private final class ColorPickerOverlayView: NSView {
    private let capture: ColorPickerScreenCapture
    private let onPick: (ColorPickerSample) -> Void
    private let onCancel: () -> Void
    private let lensDiameter: CGFloat = 118
    private let magnification: CGFloat = 8
    private var currentGlobalPoint: CGPoint
    private var currentSample: ColorPickerSample?
    private var trackingArea: NSTrackingArea?

    init(
        capture: ColorPickerScreenCapture,
        onPick: @escaping (ColorPickerSample) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.capture = capture
        self.onPick = onPick
        self.onCancel = onCancel
        self.currentGlobalPoint = NSEvent.mouseLocation
        self.currentSample = capture.sample(at: NSEvent.mouseLocation)
        super.init(frame: CGRect(origin: .zero, size: capture.frame.size))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        updateCursor()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseEntered(with event: NSEvent) {
        update(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        update(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        update(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        update(with: event)
        if let currentSample {
            onPick(currentSample)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
        } else {
            super.keyDown(with: event)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current?.cgContext else {
            return
        }

        let point = viewPoint(for: currentGlobalPoint)
        drawLens(at: point, in: context)
        drawColorBadge(near: point)
    }

    private func update(with event: NSEvent) {
        guard let window else {
            return
        }
        let location = event.locationInWindow
        currentGlobalPoint = CGPoint(
            x: window.frame.minX + location.x,
            y: window.frame.minY + location.y
        )
        currentSample = capture.sample(at: currentGlobalPoint)
        needsDisplay = true
        updateCursor()
    }

    private func updateCursor() {
        NSCursor.crosshair.set()
    }

    private func viewPoint(for globalPoint: CGPoint) -> CGPoint {
        CGPoint(
            x: globalPoint.x - capture.frame.minX,
            y: globalPoint.y - capture.frame.minY
        )
    }

    private func drawLens(at point: CGPoint, in context: CGContext) {
        guard let cropRect = capture.cropRect(
            centeredAt: currentGlobalPoint,
            diameterPoints: lensDiameter,
            magnification: magnification
        ), let crop = capture.image.cropping(to: cropRect) else {
            return
        }

        let lensRect = CGRect(
            x: point.x - lensDiameter / 2,
            y: point.y - lensDiameter / 2,
            width: lensDiameter,
            height: lensDiameter
        )

        context.saveGState()
        let path = CGPath(ellipseIn: lensRect, transform: nil)
        context.addPath(path)
        context.clip()
        context.interpolationQuality = .none
        context.draw(crop, in: lensRect)
        context.restoreGState()

        NSColor.black.withAlphaComponent(0.82).setStroke()
        let outerBorder = NSBezierPath(ovalIn: lensRect)
        outerBorder.lineWidth = 4
        outerBorder.stroke()

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let border = NSBezierPath(ovalIn: lensRect.insetBy(dx: 2, dy: 2))
        border.lineWidth = 1
        border.stroke()

        drawCrosshair(at: point)
    }

    private func drawCrosshair(at point: CGPoint) {
        let path = NSBezierPath()
        path.move(to: CGPoint(x: point.x - 7, y: point.y))
        path.line(to: CGPoint(x: point.x + 7, y: point.y))
        path.move(to: CGPoint(x: point.x, y: point.y - 7))
        path.line(to: CGPoint(x: point.x, y: point.y + 7))
        NSColor.white.setStroke()
        path.lineWidth = 1.5
        path.stroke()

        let center = NSBezierPath(ovalIn: CGRect(x: point.x - 2, y: point.y - 2, width: 4, height: 4))
        NSColor.black.setFill()
        center.fill()
    }

    private func drawColorBadge(near point: CGPoint) {
        guard let currentSample else {
            return
        }

        let badgeSize = CGSize(width: 104, height: 30)
        let badgeOrigin = constrainedBadgeOrigin(near: point, size: badgeSize)
        let badgeRect = CGRect(origin: badgeOrigin, size: badgeSize)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 6, yRadius: 6)

        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        badgePath.fill()
        NSColor.black.withAlphaComponent(0.25).setStroke()
        badgePath.lineWidth = 1
        badgePath.stroke()

        let swatchRect = CGRect(x: badgeRect.minX + 8, y: badgeRect.minY + 7, width: 16, height: 16)
        let swatch = NSBezierPath(roundedRect: swatchRect, xRadius: 3, yRadius: 3)
        NSColor(
            calibratedRed: CGFloat(currentSample.red) / 255,
            green: CGFloat(currentSample.green) / 255,
            blue: CGFloat(currentSample.blue) / 255,
            alpha: 1
        ).setFill()
        swatch.fill()

        let textRect = CGRect(x: badgeRect.minX + 31, y: badgeRect.minY + 6, width: 66, height: 18)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        currentSample.hexString.draw(in: textRect, withAttributes: attributes)
    }

    private func constrainedBadgeOrigin(near point: CGPoint, size: CGSize) -> CGPoint {
        var origin = CGPoint(
            x: point.x - size.width / 2,
            y: point.y - lensDiameter / 2 - size.height - 10
        )
        if origin.y < bounds.minY + 10 {
            origin.y = point.y + lensDiameter / 2 + 10
        }
        origin.x = min(max(origin.x, bounds.minX + 10), bounds.maxX - size.width - 10)
        origin.y = min(max(origin.y, bounds.minY + 10), bounds.maxY - size.height - 10)
        return origin
    }
}
