import AppKit
import SwiftUI

@MainActor
final class MacroTextConfigPanelController {
    private let environment: MacroTextModule
    private var panel: NSPanel?

    init(environment: MacroTextModule) {
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
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "MacroText"
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces]
        panel.contentView = NSHostingView(rootView: MacroTextSettingsView(environment: environment))
        return panel
    }
}
