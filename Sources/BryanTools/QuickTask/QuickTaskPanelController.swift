import AppKit
import SwiftUI

final class NonActivatingQuickTaskPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool {
        true
    }
}

@MainActor
final class QuickTaskPanelController {
    private let environment: QuickTaskModule
    private var panel: NSPanel?
    private var hasPlacedPanel = false

    init(environment: QuickTaskModule) {
        self.environment = environment
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        updateSize()

        if !hasPlacedPanel, let screenFrame = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: screenFrame.midX - panel.frame.width / 2,
                y: screenFrame.maxY - panel.frame.height - 120
            ))
            hasPlacedPanel = true
        } else if !hasPlacedPanel {
            panel.center()
            hasPlacedPanel = true
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingQuickTaskPanel(
            contentRect: NSRect(origin: .zero, size: QuickTaskModule.barOnlyPanelSize),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "QuickTask"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.minSize = QuickTaskModule.minimumPanelSize
        panel.maxSize = QuickTaskModule.maximumPanelSize
        panel.contentMinSize = QuickTaskModule.minimumPanelSize
        panel.contentMaxSize = QuickTaskModule.maximumPanelSize
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = DraggableHostingView(rootView: QuickTaskView(environment: environment))
        return panel
    }

    func updateSize() {
        guard let panel else {
            return
        }
        let oldFrame = panel.frame
        let currentContentRect = panel.contentRect(forFrameRect: oldFrame)
        let requestedSize = environment.panelSize
        let width = min(
            QuickTaskModule.maximumPanelSize.width,
            max(currentContentRect.width, QuickTaskModule.minimumPanelSize.width)
        )
        let contentSize = NSSize(
            width: width,
            height: requestedSize.height
        )
        let frameSize = panel.frameRect(
            forContentRect: NSRect(origin: .zero, size: contentSize)
        ).size
        let height = min(
            QuickTaskModule.maximumPanelSize.height,
            max(frameSize.height, QuickTaskModule.minimumPanelSize.height)
        )
        let newFrame = NSRect(
            x: oldFrame.minX,
            y: oldFrame.maxY - height,
            width: frameSize.width,
            height: height
        )
        panel.setFrame(newFrame, display: true, animate: false)
    }
}
