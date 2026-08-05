import AppKit
import SwiftUI

@MainActor
final class AlarmConfigurationPanelController {
    private let environment: AlarmModule
    private var panel: NSPanel?

    init(environment: AlarmModule) {
        self.environment = environment
    }

    func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            panel.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Alarm"
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.contentView = NSHostingView(rootView: AlarmConfigurationView(environment: environment))
        return panel
    }
}
