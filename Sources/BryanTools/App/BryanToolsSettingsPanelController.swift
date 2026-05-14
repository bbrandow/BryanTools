import AppKit
import SwiftUI

@MainActor
final class BryanToolsSettingsPanelController {
    private let environment: BryanToolsEnvironment
    private var panel: NSPanel?

    init(environment: BryanToolsEnvironment) {
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

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Bryan Tools Settings"
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.contentView = NSHostingView(rootView: BryanToolsSettingsView(environment: environment))
        return panel
    }
}
