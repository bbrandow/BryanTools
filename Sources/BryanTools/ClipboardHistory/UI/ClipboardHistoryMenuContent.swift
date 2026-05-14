import AppKit
import SwiftUI

struct ClipboardHistoryMenuContent: View {
    @ObservedObject var environment: ClipboardHistoryModule
    let includeAppCommands: Bool

    init(environment: ClipboardHistoryModule, includeAppCommands: Bool = false) {
        self.environment = environment
        self.includeAppCommands = includeAppCommands
    }

    var body: some View {
        Button {
            environment.showHistory()
        } label: {
            Label("Open Clipboard History (\(environment.hotKey.displayString))", systemImage: "square.stack")
        }

        Button {
            environment.capturePaused.toggle()
        } label: {
            Label(
                environment.capturePaused ? "Resume Capture" : "Pause Capture",
                systemImage: environment.capturePaused ? "play.fill" : "pause.fill"
            )
        }

        Button(role: .destructive) {
            environment.clearHistory()
        } label: {
            Label("Clear History", systemImage: "trash")
        }

        if includeAppCommands {
            Divider()

            Button {
                BryanToolsEnvironment.shared.showSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Divider()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit Bryan Tools", systemImage: "power")
            }
        }
    }
}
