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
            panel.dispose()
            panel.orderOut(nil)
        }
        panels.removeAll()
    }

    private func close(_ panel: ShotFloatPanel) {
        panel.dispose()
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
        acceptsMouseMovedEvents = true
        isMovableByWindowBackground = false
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
        makeFirstResponder(floatView)
    }

    func dispose() {
        floatView.dispose()
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
        return min(1, min(maxWidth / imageSize.width, maxHeight / imageSize.height))
    }
}
