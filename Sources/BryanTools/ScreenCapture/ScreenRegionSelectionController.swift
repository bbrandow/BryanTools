import AppKit
import Foundation

struct ScreenRegionSelection {
    let image: NSImage
    let cgImage: CGImage
    let globalRect: CGRect
}

@MainActor
final class ScreenRegionSelectionController {
    private let captures: [ColorPickerScreenCapture]
    private let onSelection: (ScreenRegionSelection) -> Void
    private let onCancel: () -> Void
    private var windows: [NSWindow] = []

    init(
        captures: [ColorPickerScreenCapture],
        onSelection: @escaping (ScreenRegionSelection) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.captures = captures
        self.onSelection = onSelection
        self.onCancel = onCancel
    }

    func show() {
        close()
        windows = captures.map { capture in
            let view = ScreenRegionSelectionView(
                capture: capture,
                onSelection: { [weak self] capture, rect in
                    self?.select(capture: capture, rect: rect)
                },
                onCancel: onCancel
            )
            let window = ScreenRegionSelectionWindow(capture: capture, contentView: view)
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

    private func select(capture: ColorPickerScreenCapture, rect: CGRect) {
        guard let croppedImage = capture.croppedImage(forGlobalRect: rect) else {
            onCancel()
            return
        }

        let selectedRect = rect.standardized.intersection(capture.frame)
        let image = NSImage(
            cgImage: croppedImage,
            size: NSSize(width: selectedRect.width, height: selectedRect.height)
        )
        onSelection(
            ScreenRegionSelection(
                image: image,
                cgImage: croppedImage,
                globalRect: selectedRect
            )
        )
    }
}

private final class ScreenRegionSelectionWindow: NSWindow {
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

private final class ScreenRegionSelectionView: NSView {
    private let capture: ColorPickerScreenCapture
    private let onSelection: (ColorPickerScreenCapture, CGRect) -> Void
    private let onCancel: () -> Void
    private var startGlobalPoint: CGPoint?
    private var currentGlobalPoint: CGPoint?

    init(
        capture: ColorPickerScreenCapture,
        onSelection: @escaping (ColorPickerScreenCapture, CGRect) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.capture = capture
        self.onSelection = onSelection
        self.onCancel = onCancel
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
        NSCursor.crosshair.set()
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        let point = globalPoint(for: event)
        startGlobalPoint = point
        currentGlobalPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentGlobalPoint = globalPoint(for: event)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        currentGlobalPoint = globalPoint(for: event)
        guard let selectionRect,
              selectionRect.width >= 4,
              selectionRect.height >= 4 else {
            onCancel()
            return
        }
        onSelection(capture, selectionRect)
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

        let dimPath = NSBezierPath(rect: bounds)
        if let selectionViewRect {
            dimPath.append(NSBezierPath(rect: selectionViewRect))
            dimPath.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(0.18).setFill()
        dimPath.fill()

        guard let selectionViewRect else {
            return
        }

        NSColor.white.withAlphaComponent(0.95).setStroke()
        let outer = NSBezierPath(rect: selectionViewRect)
        outer.lineWidth = 2
        outer.stroke()

        NSColor.systemBlue.withAlphaComponent(0.9).setStroke()
        let inner = NSBezierPath(rect: selectionViewRect.insetBy(dx: 1, dy: 1))
        inner.lineWidth = 1
        inner.stroke()
    }

    private var selectionRect: CGRect? {
        guard let startGlobalPoint, let currentGlobalPoint else {
            return nil
        }
        return CGRect(
            x: min(startGlobalPoint.x, currentGlobalPoint.x),
            y: min(startGlobalPoint.y, currentGlobalPoint.y),
            width: abs(startGlobalPoint.x - currentGlobalPoint.x),
            height: abs(startGlobalPoint.y - currentGlobalPoint.y)
        ).intersection(capture.frame)
    }

    private var selectionViewRect: CGRect? {
        guard let selectionRect else {
            return nil
        }
        return CGRect(
            x: selectionRect.minX - capture.frame.minX,
            y: selectionRect.minY - capture.frame.minY,
            width: selectionRect.width,
            height: selectionRect.height
        )
    }

    private func globalPoint(for event: NSEvent) -> CGPoint {
        guard let window else {
            return .zero
        }
        let location = event.locationInWindow
        return CGPoint(
            x: window.frame.minX + location.x,
            y: window.frame.minY + location.y
        )
    }
}
