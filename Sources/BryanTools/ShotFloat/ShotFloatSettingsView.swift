import AppKit
import BryanToolsShared
import Carbon
import SwiftUI

struct ShotFloatSettingsView: View {
    @ObservedObject var environment: ShotFloatModule
    @State private var recordingShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ShotFloat")
                .font(.system(size: 22, weight: .semibold))

            settingsSection("Shortcuts") {
                settingsRow("Capture ShotFloat") {
                    shortcutControls
                }
            }

            if let message = environment.lastErrorMessage {
                settingsSection("Last Error") {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            Group {
                if recordingShortcut {
                    KeyEventHandlingView { event in
                        handleHotKeyEvent(event)
                    }
                }
            }
        )
    }

    private var shortcutControls: some View {
        HStack(spacing: 8) {
            Text(environment.hotKey.displayString)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)

            Button {
                recordingShortcut.toggle()
            } label: {
                Label(recordingShortcut ? "Recording" : "Record", systemImage: recordingShortcut ? "record.circle" : "keyboard")
            }

            Button {
                recordingShortcut = false
                environment.resetHotKey()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
        }
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                content()
            }
        }
    }

    private func settingsRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .frame(width: 140, alignment: .leading)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            content()
        }
    }

    private func handleHotKeyEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape) {
            recordingShortcut = false
            return true
        }

        guard let hotKey = AppHotKey(event: event) else {
            return true
        }

        environment.updateHotKey(hotKey)
        if hotKey.hasPrimaryModifier {
            recordingShortcut = false
        }
        return true
    }
}
