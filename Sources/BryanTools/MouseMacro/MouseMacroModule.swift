import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class MouseMacroModule: ObservableObject, ToolModule {
    static let shared = MouseMacroModule(preferences: .load())

    let id = ToolIdentifier.mouseMacro
    let displayName = ToolIdentifier.mouseMacro.displayName
    let systemImage = "computermouse"

    @Published private(set) var mappings: [MouseMacroMapping]
    @Published private(set) var pendingButtonNumber: Int64?
    @Published private(set) var isCapturingButton = false
    @Published private(set) var lastTriggeredAt: Date?
    @Published var lastStatusMessage: String?
    @Published var lastErrorMessage: String?

    private var preferences: MouseMacroPreferences
    private var eventTap: MouseMacroEventTap?
    private var isRunning = false

    private init(preferences: MouseMacroPreferences) {
        self.preferences = preferences
        self.mappings = preferences.mappings
    }

    func start() {
        isRunning = true
        if !mappings.isEmpty {
            startEventTap()
        }
    }

    func stop() {
        isRunning = false
        eventTap?.stop()
        eventTap = nil
        isCapturingButton = false
    }

    func menuContent() -> AnyView {
        AnyView(MouseMacroMenuContent(environment: self))
    }

    func settingsView() -> AnyView {
        AnyView(MouseMacroSettingsView(environment: self))
    }

    func captureNextButton() {
        guard AccessibilityPermissionService.ensurePermission(promptIfNeeded: true) else {
            lastErrorMessage = "Enable Accessibility permission for Bryan Tools to listen for mouse buttons."
            return
        }
        pendingButtonNumber = nil
        isCapturingButton = true
        lastStatusMessage = "Press the mouse button to map."
        lastErrorMessage = nil
        startEventTap()
    }

    func cancelCapture() {
        isCapturingButton = false
        lastStatusMessage = nil
        stopEventTapIfIdle()
    }

    func clearPendingButton() {
        pendingButtonNumber = nil
        isCapturingButton = false
        lastStatusMessage = nil
        stopEventTapIfIdle()
    }

    func addMapping(buttonNumber: Int64, macroText: String) {
        guard validate(buttonNumber: buttonNumber, macroText: macroText, replacing: nil) else {
            return
        }
        mappings.append(MouseMacroMapping(buttonNumber: buttonNumber, macroText: macroText))
        persistMappings()
        pendingButtonNumber = nil
        lastStatusMessage = "Added mouse button \(buttonNumber)."
        ensureEventTapForMappings()
    }

    func updateMapping(_ mapping: MouseMacroMapping, buttonNumber: Int64, macroText: String) {
        guard mappings.contains(where: { $0.id == mapping.id }) else {
            lastErrorMessage = "MouseMacro mapping no longer exists."
            return
        }
        guard validate(buttonNumber: buttonNumber, macroText: macroText, replacing: mapping.id) else {
            return
        }

        mappings = mappings.map { item in
            guard item.id == mapping.id else {
                return item
            }
            return MouseMacroMapping(id: item.id, buttonNumber: buttonNumber, macroText: macroText)
        }
        persistMappings()
        pendingButtonNumber = nil
        lastStatusMessage = "Updated mouse button \(buttonNumber)."
        ensureEventTapForMappings()
    }

    func deleteMapping(_ mapping: MouseMacroMapping) {
        mappings.removeAll { $0.id == mapping.id }
        persistMappings()
        if mappings.isEmpty {
            lastStatusMessage = nil
        } else {
            lastStatusMessage = "Deleted mouse button \(mapping.buttonNumber)."
        }
        stopEventTapIfIdle()
    }

    func triggerMacro(_ mapping: MouseMacroMapping) {
        runMacro(mapping.macroText, sourceButtonNumber: mapping.buttonNumber)
    }

    private func startEventTap() {
        guard eventTap == nil else {
            return
        }
        let tap = MouseMacroEventTap { [weak self] buttonNumber in
            self?.handleButton(buttonNumber) ?? false
        }
        do {
            try tap.start()
            eventTap = tap
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func stopEventTapIfIdle() {
        guard mappings.isEmpty, !isCapturingButton else {
            return
        }
        eventTap?.stop()
        eventTap = nil
    }

    private func ensureEventTapForMappings() {
        guard isRunning, !mappings.isEmpty else {
            return
        }
        startEventTap()
    }

    private func handleButton(_ buttonNumber: Int64) -> Bool {
        if isCapturingButton {
            pendingButtonNumber = buttonNumber
            isCapturingButton = false
            lastStatusMessage = "Detected mouse button \(buttonNumber)."
            lastErrorMessage = nil
            stopEventTapIfIdle()
            return true
        }

        guard let mapping = mappings.first(where: { $0.buttonNumber == buttonNumber }) else {
            return false
        }
        runMacro(mapping.macroText, sourceButtonNumber: buttonNumber)
        return true
    }

    private func runMacro(_ macroText: String, sourceButtonNumber: Int64) {
        guard let commands = MouseMacroCommandParser.parse(macroText) else {
            lastErrorMessage = "MouseMacro command is invalid."
            return
        }
        for command in commands {
            post(command)
        }
        lastTriggeredAt = Date()
        lastStatusMessage = "Triggered mouse button \(sourceButtonNumber)."
        lastErrorMessage = nil
    }

    private func validate(buttonNumber: Int64, macroText: String, replacing id: UUID?) -> Bool {
        guard buttonNumber >= 0 else {
            lastErrorMessage = "MouseMacro button number is invalid."
            return false
        }
        guard MouseMacroCommandParser.parse(macroText) != nil else {
            lastErrorMessage = "MouseMacro command is invalid."
            return false
        }
        guard !mappings.contains(where: { $0.id != id && $0.buttonNumber == buttonNumber }) else {
            lastErrorMessage = "Mouse button \(buttonNumber) is already mapped."
            return false
        }
        lastErrorMessage = nil
        return true
    }

    private func persistMappings() {
        mappings.sort {
            if $0.buttonNumber != $1.buttonNumber {
                return $0.buttonNumber < $1.buttonNumber
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        preferences.mappings = mappings
        preferences.save()
    }

    private func post(_ command: MouseMacroKeyCommand) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let keyDown = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(command.keyCode),
            keyDown: true
        ),
        let keyUp = CGEvent(
            keyboardEventSource: source,
            virtualKey: CGKeyCode(command.keyCode),
            keyDown: false
        ) else {
            return
        }
        keyDown.flags = command.flags
        keyUp.flags = command.flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}
