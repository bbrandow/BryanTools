import AppKit
import BryanToolsShared
import Carbon
import SwiftUI

struct ColorPickerSettingsView: View {
    @ObservedObject var environment: ColorPickerModule
    @State private var recordingShortcut = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("ColorPicker")
                .font(.system(size: 22, weight: .semibold))

            settingsSection("Shortcuts") {
                settingsRow("Pick Color") {
                    shortcutControls
                }
            }

            if let lastHexColor = environment.lastHexColor {
                settingsSection("Last Color") {
                    HStack(spacing: 10) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: NSColor(hexString: lastHexColor) ?? .clear))
                            .frame(width: 28, height: 20)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.secondary.opacity(0.35))
                            )

                        Text(lastHexColor)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)

                        Button {
                            environment.copyLastColor()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
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

private extension NSColor {
    convenience init?(hexString: String) {
        let hex = hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard hex.count == 6,
              let value = Int(hex, radix: 16) else {
            return nil
        }

        self.init(
            calibratedRed: CGFloat((value >> 16) & 0xff) / 255,
            green: CGFloat((value >> 8) & 0xff) / 255,
            blue: CGFloat(value & 0xff) / 255,
            alpha: 1
        )
    }
}
