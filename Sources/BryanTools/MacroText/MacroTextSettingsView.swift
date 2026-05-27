import AppKit
import BryanToolsShared
import Carbon
import SwiftUI

struct MacroTextSettingsView: View {
    @ObservedObject var environment: MacroTextModule
    @State private var recordingShortcut = false
    @State private var command = "/"
    @State private var replacement = ""
    @State private var editingReplacement: MacroTextReplacement?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("MacroText")
                .font(.system(size: 22, weight: .semibold))

            settingsSection("Shortcuts") {
                settingsRow("Configure") {
                    shortcutControls
                }
            }

            settingsSection(editingReplacement == nil ? "Add Replacement" : "Edit Replacement") {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    TextField("/command", text: $command)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 160)

                    Image(systemName: "arrow.right")
                        .foregroundStyle(.secondary)

                    TextField("Replacement text", text: $replacement, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)

                    Button {
                        saveReplacement()
                    } label: {
                        Label(editingReplacement == nil ? "Add" : "Save", systemImage: editingReplacement == nil ? "plus" : "checkmark")
                    }
                    .disabled(command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || replacement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if editingReplacement != nil {
                        Button {
                            clearEditor()
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                    }
                }
            }

            settingsSection("Replacements") {
                if environment.replacements.isEmpty {
                    ContentUnavailableView("No MacroText Replacements", systemImage: "text.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    VStack(spacing: 0) {
                        ForEach(environment.replacements) { item in
                            MacroTextReplacementRow(
                                replacement: item,
                                isEditing: editingReplacement?.id == item.id,
                                edit: {
                                    editReplacement(item)
                                },
                                delete: {
                                    if editingReplacement?.id == item.id {
                                        clearEditor()
                                    }
                                    environment.deleteReplacement(item)
                                }
                            )
                            Divider()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.18))
                    )
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

    private func saveReplacement() {
        if let editingReplacement {
            environment.updateReplacement(editingReplacement, command: command, replacement: replacement)
        } else {
            environment.addOrUpdateReplacement(command: command, replacement: replacement)
        }

        if environment.lastErrorMessage == nil {
            clearEditor()
        }
    }

    private func editReplacement(_ item: MacroTextReplacement) {
        editingReplacement = item
        command = item.command
        replacement = item.replacement
    }

    private func clearEditor() {
        editingReplacement = nil
        command = "/"
        replacement = ""
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

private struct MacroTextReplacementRow: View {
    let replacement: MacroTextReplacement
    let isEditing: Bool
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(replacement.command)
                .font(.system(.body, design: .monospaced))
                .frame(width: 140, alignment: .leading)
                .textSelection(.enabled)

            Text(replacement.replacement)
                .lineLimit(3)
                .textSelection(.enabled)

            Spacer(minLength: 12)

            Button {
                edit()
            } label: {
                Image(systemName: isEditing ? "pencil.circle.fill" : "pencil")
            }
            .help(isEditing ? "Editing replacement" : "Edit replacement")

            Button(role: .destructive) {
                delete()
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete replacement")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background((isEditing ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.45)))
    }
}
