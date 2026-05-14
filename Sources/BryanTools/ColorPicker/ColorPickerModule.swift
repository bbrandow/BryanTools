import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class ColorPickerModule: ObservableObject, ToolModule {
    static let shared = ColorPickerModule(preferences: .load())

    let id = ToolIdentifier.colorPicker
    let displayName = ToolIdentifier.colorPicker.displayName
    let systemImage = "eyedropper"

    @Published private(set) var hotKey: AppHotKey
    @Published private(set) var isPicking = false
    @Published private(set) var lastHexColor: String?
    @Published var lastErrorMessage: String?

    private enum HotKeyID {
        static let pickColor: HotKeyController.Identifier = 100
    }

    private let hotKeyController = HotKeyController()
    private var preferences: ColorPickerPreferences
    private var overlayController: ColorPickerOverlayController?
    private var isRunning = false
    private var appToRestoreFocus: NSRunningApplication?

    private init(preferences: ColorPickerPreferences) {
        self.preferences = preferences
        self.hotKey = preferences.hotKey
        self.lastHexColor = preferences.lastHexColor
    }

    func start() {
        isRunning = true
        registerHotKey()
    }

    func stop() {
        isRunning = false
        endPicking(restoreFocus: false)
        hotKeyController.unregisterAll()
    }

    func menuContent() -> AnyView {
        AnyView(ColorPickerMenuContent(environment: self))
    }

    func settingsView() -> AnyView {
        AnyView(ColorPickerSettingsView(environment: self))
    }

    func beginPicking() {
        if isPicking {
            endPicking(restoreFocus: true)
            return
        }

        guard ColorPickerScreenCapture.ensurePermission(promptIfNeeded: true) else {
            lastErrorMessage = "Enable Screen Recording permission for Bryan Tools to pick colors from the screen."
            return
        }

        do {
            let captures = try ColorPickerScreenCapture.captureScreens()
            guard !captures.isEmpty else {
                lastErrorMessage = "Unable to capture the screen for color picking."
                return
            }

            rememberAppForFocusRestore()
            let controller = ColorPickerOverlayController(
                captures: captures,
                onPick: { [weak self] sample in
                    self?.completePicking(sample)
                },
                onCancel: { [weak self] in
                    self?.endPicking(restoreFocus: true)
                }
            )
            overlayController = controller
            isPicking = true
            lastErrorMessage = nil
            controller.show()
        } catch {
            lastErrorMessage = error.localizedDescription
            endPicking(restoreFocus: true)
        }
    }

    func copyLastColor() {
        guard let lastHexColor else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastHexColor, forType: .string)
    }

    func updateHotKey(_ newHotKey: AppHotKey) {
        guard newHotKey.hasPrimaryModifier else {
            lastErrorMessage = "Shortcut must include Command, Control, or Option."
            return
        }

        let previousHotKey = hotKey
        do {
            if isRunning {
                try hotKeyController.register(newHotKey, identifier: HotKeyID.pickColor) { [weak self] in
                    self?.beginPicking()
                }
            }
            hotKey = newHotKey
            preferences.hotKey = newHotKey
            preferences.save()
            lastErrorMessage = nil
        } catch {
            if isRunning {
                try? hotKeyController.register(previousHotKey, identifier: HotKeyID.pickColor) { [weak self] in
                    self?.beginPicking()
                }
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    func resetHotKey() {
        updateHotKey(.defaultColorPickerValue)
    }

    private func registerHotKey() {
        do {
            try hotKeyController.register(hotKey, identifier: HotKeyID.pickColor) { [weak self] in
                self?.beginPicking()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func completePicking(_ sample: ColorPickerSample) {
        let hex = sample.hexString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(hex, forType: .string)
        lastHexColor = hex
        preferences.lastHexColor = hex
        preferences.save()
        lastErrorMessage = nil
        endPicking(restoreFocus: true)
    }

    private func endPicking(restoreFocus: Bool) {
        overlayController?.close()
        overlayController = nil
        isPicking = false
        if restoreFocus {
            restorePreviousAppFocus()
        }
    }

    private func rememberAppForFocusRestore() {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return
        }
        appToRestoreFocus = frontmostApp
    }

    private func restorePreviousAppFocus() {
        guard let app = appToRestoreFocus,
              !app.isTerminated else {
            appToRestoreFocus = nil
            return
        }

        appToRestoreFocus = nil
        DispatchQueue.main.async {
            app.activate(options: [])
        }
    }
}
