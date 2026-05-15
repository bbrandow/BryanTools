import AppKit
import SwiftUI

final class NonActivatingHistoryPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}

@MainActor
final class HistoryPanelController: NSObject, NSWindowDelegate {
    private let environment: ClipboardHistoryModule
    private var panel: NSPanel?

    init(environment: ClipboardHistoryModule) {
        self.environment = environment
        super.init()
    }

    func show() {
        if panel?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true)
            panel?.orderFrontRegardless()
            panel?.makeKeyAndOrderFront(nil)
            return
        }

        let panel = makePanel()
        self.panel = panel

        if let screenFrame = NSScreen.main?.visibleFrame {
            let origin = NSPoint(
                x: screenFrame.midX - panel.frame.width / 2,
                y: screenFrame.midY - panel.frame.height / 2
            )
            panel.setFrameOrigin(origin)
        } else {
            panel.center()
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else {
            return
        }
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NonActivatingHistoryPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
            styleMask: [.nonactivatingPanel, .titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Clipboard History"
        panel.isReleasedWhenClosed = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titlebarAppearsTransparent = true
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: HistoryView(environment: environment))
        return panel
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSPanel === panel else {
            return
        }
        panel?.contentView = nil
        panel = nil
        environment.historyPanelDidClose()
    }
}
