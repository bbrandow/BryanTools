import AppKit
import BryanToolsShared
import Carbon
import SwiftUI

struct BryanToolsSettingsView: View {
    @ObservedObject var environment: BryanToolsEnvironment
    @ObservedObject private var clipboardHistory: ClipboardHistoryModule
    @ObservedObject private var colorPicker: ColorPickerModule
    @ObservedObject private var macroText: MacroTextModule
    @ObservedObject private var mouseMacro: MouseMacroModule
    @ObservedObject private var quickTask: QuickTaskModule
    @ObservedObject private var shotFloat: ShotFloatModule
    @ObservedObject private var screenOCR: ScreenOCRModule
    @ObservedObject private var diskSpaceMonitor: DiskSpaceMonitorModule
    @ObservedObject private var utcHour: UTCHourModule
    @ObservedObject private var vehicleMotionCues: VehicleMotionCuesModule
    @ObservedObject private var updater: BryanToolsUpdater
    @ObservedObject private var autoStart: BryanToolsAutoStartController

    @State private var recordingHotKey: SettingsHotKeyTarget?
    @State private var diskWarningText = ""

    init(environment: BryanToolsEnvironment) {
        self.environment = environment
        self.clipboardHistory = environment.clipboardHistory
        self.colorPicker = environment.colorPicker
        self.macroText = environment.macroText
        self.mouseMacro = environment.mouseMacro
        self.quickTask = environment.quickTask
        self.shotFloat = environment.shotFloat
        self.screenOCR = environment.screenOCR
        self.diskSpaceMonitor = environment.diskSpaceMonitor
        self.utcHour = environment.utcHour
        self.vehicleMotionCues = environment.vehicleMotionCues
        self.updater = environment.updater
        self.autoStart = environment.autoStart
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                settingsSection("Hotkeys") {
                    hotKeyRow(
                        "Clipboard History",
                        systemImage: clipboardHistory.systemImage,
                        hotKey: clipboardHistory.hotKey,
                        target: .clipboardHistory,
                        reset: clipboardHistory.resetHotKey
                    )

                    hotKeyRow(
                        "Paste Plain Text",
                        systemImage: "textformat",
                        hotKey: clipboardHistory.plainTextPasteHotKey,
                        target: .pastePlainText,
                        reset: clipboardHistory.resetPlainTextPasteHotKey
                    )

                    hotKeyRow(
                        "Color Picker",
                        systemImage: colorPicker.systemImage,
                        hotKey: colorPicker.hotKey,
                        target: .colorPicker,
                        reset: colorPicker.resetHotKey
                    )

                    hotKeyRow(
                        "MacroText",
                        systemImage: macroText.systemImage,
                        hotKey: macroText.hotKey,
                        target: .macroText,
                        reset: macroText.resetHotKey,
                        accessory: AnyView(
                            Button {
                                macroText.showConfig()
                            } label: {
                                Label("Configure MacroText", systemImage: "gearshape")
                            }
                            .labelStyle(.iconOnly)
                            .controlSize(.small)
                            .help("Open MacroText settings")
                        )
                    )

                    hotKeyRow(
                        "QuickTask",
                        systemImage: quickTask.systemImage,
                        hotKey: quickTask.hotKey,
                        target: .quickTask,
                        reset: quickTask.resetHotKey
                    )

                    hotKeyRow(
                        "ShotFloat",
                        systemImage: shotFloat.systemImage,
                        hotKey: shotFloat.hotKey,
                        target: .shotFloat,
                        reset: shotFloat.resetHotKey
                    )

                    hotKeyRow(
                        "Screen OCR",
                        systemImage: screenOCR.systemImage,
                        hotKey: screenOCR.hotKey,
                        target: .screenOCR,
                        reset: screenOCR.resetHotKey
                    )
                }

                HStack(alignment: .top, spacing: 14) {
                    settingsSection("Clipboard History") {
                        compactRow("Capture") {
                            Toggle("Paused", isOn: capturePausedBinding)
                                .toggleStyle(.checkbox)
                        }

                        compactRow("Retention") {
                            Stepper(value: retentionDaysBinding, in: ClipboardHistoryPreferences.minimumRetentionDays...ClipboardHistoryPreferences.maximumRetentionDays) {
                                Text("\(clipboardHistory.retentionDays) days")
                                    .frame(width: 80, alignment: .trailing)
                            }
                        }

                        compactRow("Storage") {
                            HStack(spacing: 8) {
                                Text(clipboardHistory.storagePath)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .trailing)

                                Button {
                                    clipboardHistory.chooseStorageLocation()
                                } label: {
                                    Label("Choose", systemImage: "folder")
                                }
                                .labelStyle(.iconOnly)
                                .help("Choose storage location")

                                Button {
                                    clipboardHistory.resetStorageLocation()
                                } label: {
                                    Label("Reset", systemImage: "arrow.counterclockwise")
                                }
                                .labelStyle(.iconOnly)
                                .help("Reset storage location")
                            }
                        }

                        HStack {
                            Spacer()
                            Button(role: .destructive) {
                                clipboardHistory.clearHistory()
                            } label: {
                                Label("Clear History", systemImage: "trash")
                            }
                            .controlSize(.small)
                        }
                    }

                    settingsSection("Disk Space") {
                        compactRow("Menu Bar") {
                            Toggle("Show", isOn: diskSpaceEnabledBinding)
                                .toggleStyle(.checkbox)
                        }

                        compactRow("Warning Below") {
                            HStack(spacing: 8) {
                                TextField("50", text: $diskWarningText)
                                    .font(.system(.body, design: .monospaced))
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 70)
                                    .textFieldStyle(.roundedBorder)
                                    .onSubmit(commitDiskWarningText)

                                Text("GB")
                                    .foregroundStyle(.secondary)

                                Stepper("", value: diskWarningThresholdBinding, in: DiskSpaceMonitorPreferences.minimumWarningThresholdGB...DiskSpaceMonitorPreferences.maximumWarningThresholdGB)
                                    .labelsHidden()
                            }
                        }
                    }
                }

                settingsSection("Application") {
                    compactRow("Auto Start") {
                        Toggle("Start Bryan Tools on login", isOn: autoStartEnabledBinding)
                            .toggleStyle(.checkbox)
                    }

                    compactRow("UTC Hour") {
                        Toggle("Show in menu bar", isOn: utcHourEnabledBinding)
                            .toggleStyle(.checkbox)
                    }

                    compactRow("Motion Cues") {
                        Toggle("Show toggle in menu bar", isOn: vehicleMotionCuesTrayEnabledBinding)
                            .toggleStyle(.checkbox)
                    }

                    compactRow("Source") {
                        HStack(spacing: 8) {
                            Text(updater.sourceRootPath)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .trailing)

                            Button {
                                updater.chooseSourceRoot()
                            } label: {
                                Label("Choose", systemImage: "folder")
                            }
                            .labelStyle(.iconOnly)
                            .help("Choose BryanTools source folder")

                            Button {
                                updater.resetSourceRoot()
                            } label: {
                                Label("Reset", systemImage: "arrow.counterclockwise")
                            }
                            .labelStyle(.iconOnly)
                            .help("Reset updater source folder")
                        }
                    }

                    compactRow("Updater") {
                        Button {
                            updater.runUpdate()
                        } label: {
                            Label(updater.isUpdating ? "Updating" : "Update Now", systemImage: "arrow.down.circle")
                        }
                        .disabled(updater.isUpdating)
                    }

                    if let message = updater.lastStatusMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }

                settingsSection("MouseMacro") {
                    MouseMacroCompactSettingsView(environment: mouseMacro)
                }

                if !statusMessages.isEmpty {
                    settingsSection("Status") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(statusMessages, id: \.self) { message in
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(width: 680, height: 620, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            Group {
                if recordingHotKey != nil {
                    KeyEventHandlingView { event in
                        handleHotKeyEvent(event)
                    }
                }
            }
        )
        .onAppear {
            syncDiskWarningText()
        }
        .onChange(of: diskSpaceMonitor.warningThresholdGB) { _, _ in
            syncDiskWarningText()
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)

            Text("Bryan Tools")
                .font(.system(size: 22, weight: .semibold))

            Spacer()
        }
    }

    private var statusMessages: [String] {
        [
            prefixedError("Clipboard History", clipboardHistory.lastErrorMessage),
            prefixedError("Color Picker", colorPicker.lastErrorMessage),
            prefixedError("MacroText", macroText.lastErrorMessage),
            prefixedError("MouseMacro", mouseMacro.lastErrorMessage),
            prefixedError("QuickTask", quickTask.lastErrorMessage),
            prefixedError("ShotFloat", shotFloat.lastErrorMessage),
            prefixedError("Screen OCR", screenOCR.lastErrorMessage),
            prefixedError("Disk Space", diskSpaceMonitor.lastErrorMessage),
            prefixedError("UTC Hour", utcHour.lastErrorMessage),
            prefixedError("Vehicle Motion Cues", vehicleMotionCues.lastErrorMessage),
            prefixedError("Auto Start", autoStart.lastErrorMessage),
            prefixedError("Updater", updater.lastErrorMessage)
        ].compactMap { $0 }
    }

    private var capturePausedBinding: Binding<Bool> {
        Binding(
            get: { clipboardHistory.capturePaused },
            set: { clipboardHistory.capturePaused = $0 }
        )
    }

    private var retentionDaysBinding: Binding<Int> {
        Binding(
            get: { clipboardHistory.retentionDays },
            set: { clipboardHistory.updateRetentionDays($0) }
        )
    }

    private var diskSpaceEnabledBinding: Binding<Bool> {
        Binding(
            get: { diskSpaceMonitor.isEnabled },
            set: { diskSpaceMonitor.updateEnabled($0) }
        )
    }

    private var diskWarningThresholdBinding: Binding<Int> {
        Binding(
            get: { diskSpaceMonitor.warningThresholdGB },
            set: { value in
                diskSpaceMonitor.updateWarningThresholdGB(value)
                syncDiskWarningText()
            }
        )
    }

    private var autoStartEnabledBinding: Binding<Bool> {
        Binding(
            get: { autoStart.isEnabled },
            set: { autoStart.updateEnabled($0) }
        )
    }

    private var utcHourEnabledBinding: Binding<Bool> {
        Binding(
            get: { utcHour.isEnabled },
            set: { utcHour.updateEnabled($0) }
        )
    }

    private var vehicleMotionCuesTrayEnabledBinding: Binding<Bool> {
        Binding(
            get: { vehicleMotionCues.isTrayEnabled },
            set: { vehicleMotionCues.updateTrayEnabled($0) }
        )
    }

    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hotKeyRow(
        _ title: String,
        systemImage: String,
        hotKey: AppHotKey,
        target: SettingsHotKeyTarget,
        reset: @escaping () -> Void,
        accessory: AnyView? = nil
    ) -> some View {
        HStack(spacing: 12) {
            Label(title, systemImage: systemImage)
                .frame(width: 168, alignment: .leading)
                .lineLimit(1)

            Text(hotKey.displayString)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .textSelection(.enabled)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let accessory {
                accessory
            }

            Button {
                recordingHotKey = recordingHotKey == target ? nil : target
            } label: {
                Label(
                    recordingHotKey == target ? "Recording Shortcut" : "Record Shortcut",
                    systemImage: recordingHotKey == target ? "record.circle.fill" : "keyboard"
                )
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .help(recordingHotKey == target ? "Recording shortcut. Press Escape to cancel." : "Record shortcut")

            Button {
                recordingHotKey = nil
                reset()
            } label: {
                Label("Reset", systemImage: "arrow.counterclockwise")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .help("Reset shortcut")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func compactRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.primary)
                .frame(width: 96, alignment: .leading)

            Spacer(minLength: 8)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func handleHotKeyEvent(_ event: NSEvent) -> Bool {
        if event.keyCode == UInt16(kVK_Escape) {
            recordingHotKey = nil
            return true
        }

        guard let recordingHotKey,
              let hotKey = AppHotKey(event: event) else {
            return true
        }

        switch recordingHotKey {
        case .clipboardHistory:
            clipboardHistory.updateHotKey(hotKey)
        case .pastePlainText:
            clipboardHistory.updatePlainTextPasteHotKey(hotKey)
        case .colorPicker:
            colorPicker.updateHotKey(hotKey)
        case .macroText:
            macroText.updateHotKey(hotKey)
        case .quickTask:
            quickTask.updateHotKey(hotKey)
        case .shotFloat:
            shotFloat.updateHotKey(hotKey)
        case .screenOCR:
            screenOCR.updateHotKey(hotKey)
        }

        if hotKey.hasPrimaryModifier {
            self.recordingHotKey = nil
        }
        return true
    }

    private func commitDiskWarningText() {
        let filtered = diskWarningText.filter(\.isNumber)
        if let value = Int(filtered) {
            diskSpaceMonitor.updateWarningThresholdGB(value)
        }
        syncDiskWarningText()
    }

    private func syncDiskWarningText() {
        diskWarningText = "\(diskSpaceMonitor.warningThresholdGB)"
    }

    private func prefixedError(_ prefix: String, _ message: String?) -> String? {
        guard let message, !message.isEmpty else {
            return nil
        }
        return "\(prefix): \(message)"
    }
}

private enum SettingsHotKeyTarget: Equatable {
    case clipboardHistory
    case pastePlainText
    case colorPicker
    case macroText
    case quickTask
    case shotFloat
    case screenOCR
}

private struct MouseMacroCompactSettingsView: View {
    @ObservedObject var environment: MouseMacroModule

    @State private var editingMapping: MouseMacroMapping?
    @State private var selectedButtonNumber: Int64?
    @State private var macroText = MouseMacroPreferences.defaultMacroText

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(buttonText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)

                Button {
                    environment.captureNextButton()
                } label: {
                    Label(environment.isCapturingButton ? "Listening" : "Map Next", systemImage: "scope")
                }
                .controlSize(.small)

                if environment.isCapturingButton {
                    Button {
                        environment.cancelCapture()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .controlSize(.small)
                }

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                TextField("cmd+shift+ctrl+4", text: $macroText)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)

                Button {
                    save()
                } label: {
                    Label(editingMapping == nil ? "Add" : "Save", systemImage: editingMapping == nil ? "plus" : "checkmark")
                }
                .controlSize(.small)
                .disabled(selectedButtonNumber == nil || macroText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if editingMapping != nil || selectedButtonNumber != nil || macroText != MouseMacroPreferences.defaultMacroText {
                    Button {
                        resetEditor()
                    } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                    }
                    .controlSize(.small)
                }
            }

            if environment.mappings.isEmpty {
                Text("No mouse macros configured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(environment.mappings) { mapping in
                        MouseMacroMappingRow(
                            mapping: mapping,
                            isEditing: editingMapping?.id == mapping.id,
                            trigger: {
                                environment.triggerMacro(mapping)
                            },
                            edit: {
                                edit(mapping)
                            },
                            delete: {
                                if editingMapping?.id == mapping.id {
                                    resetEditor()
                                }
                                environment.deleteMapping(mapping)
                            }
                        )
                        if mapping.id != environment.mappings.last?.id {
                            Divider()
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18))
                )
            }

            Text(environment.lastStatusMessage ?? "Maps extra mouse buttons that macOS exposes. If the haptic button never registers here, Logitech is not exposing it as a public mouse event.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onChange(of: environment.pendingButtonNumber) { _, buttonNumber in
            if let buttonNumber {
                selectedButtonNumber = buttonNumber
            }
        }
    }

    private var buttonText: String {
        if environment.isCapturingButton {
            return "Listening..."
        }
        guard let selectedButtonNumber else {
            return "Button: not selected"
        }
        return "Button \(selectedButtonNumber)"
    }

    private func save() {
        guard let selectedButtonNumber else {
            return
        }
        if let editingMapping {
            environment.updateMapping(editingMapping, buttonNumber: selectedButtonNumber, macroText: macroText)
        } else {
            environment.addMapping(buttonNumber: selectedButtonNumber, macroText: macroText)
        }
        if environment.lastErrorMessage == nil {
            resetEditor()
        }
    }

    private func edit(_ mapping: MouseMacroMapping) {
        editingMapping = mapping
        selectedButtonNumber = mapping.buttonNumber
        macroText = mapping.macroText
    }

    private func resetEditor() {
        editingMapping = nil
        selectedButtonNumber = nil
        macroText = MouseMacroPreferences.defaultMacroText
        environment.clearPendingButton()
    }
}

private struct MouseMacroMappingRow: View {
    let mapping: MouseMacroMapping
    let isEditing: Bool
    let trigger: () -> Void
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("Button \(mapping.buttonNumber)")
                .font(.system(.caption, design: .monospaced))
                .frame(width: 82, alignment: .leading)

            Text(mapping.macroText)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                trigger()
            } label: {
                Image(systemName: "play.fill")
            }
            .buttonStyle(.plain)
            .help("Run macro")

            Button {
                edit()
            } label: {
                Image(systemName: isEditing ? "pencil.circle.fill" : "pencil")
            }
            .buttonStyle(.plain)
            .help("Edit macro")

            Button(role: .destructive) {
                delete()
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .help("Delete macro")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isEditing ? Color.accentColor.opacity(0.12) : Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }
}
