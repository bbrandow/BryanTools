import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class ScreenFloatModule: ObservableObject, ToolModule {
    static let shared = ScreenFloatModule(preferences: .load())

    let id = ToolIdentifier.screenFloat
    let displayName = ToolIdentifier.screenFloat.displayName
    let systemImage = "rectangle.dashed"

    @Published private(set) var hotKey: AppHotKey
    @Published private(set) var isCapturing = false
    @Published var lastErrorMessage: String?

    private enum HotKeyID {
        static let captureFloatingScreenshot: HotKeyController.Identifier = 400
    }

    private let hotKeyController = HotKeyController()
    private var preferences: ScreenFloatPreferences
    private var selectionController: ScreenFloatSelectionController?
    private var isRunning = false
    private var appToRestoreFocus: NSRunningApplication?

    private init(preferences: ScreenFloatPreferences) {
        self.preferences = preferences
        self.hotKey = preferences.hotKey
    }

    func start() {
        isRunning = true
        registerHotKey()
    }

    func stop() {
        isRunning = false
        cancelCapture(restoreFocus: false)
        hotKeyController.unregisterAll()
        ScreenFloatWindowManager.shared.closeAll()
    }

    func menuContent() -> AnyView {
        AnyView(ScreenFloatMenuContent(environment: self))
    }

    func settingsView() -> AnyView {
        AnyView(ScreenFloatSettingsView(environment: self))
    }

    func beginCapture() {
        if isCapturing {
            cancelCapture(restoreFocus: true)
            return
        }

        guard ColorPickerScreenCapture.ensurePermission(promptIfNeeded: true) else {
            lastErrorMessage = "Enable Screen Recording permission for Bryan Tools to capture floating screenshots."
            return
        }

        do {
            let captures = try ColorPickerScreenCapture.captureScreens()
            rememberAppForFocusRestore()
            let controller = ScreenFloatSelectionController(
                captures: captures,
                onSelection: { [weak self] image in
                    self?.completeCapture(image)
                },
                onCancel: { [weak self] in
                    self?.cancelCapture(restoreFocus: true)
                }
            )
            selectionController = controller
            isCapturing = true
            lastErrorMessage = nil
            controller.show()
        } catch {
            lastErrorMessage = error.localizedDescription
            cancelCapture(restoreFocus: true)
        }
    }

    func floatImage(_ image: NSImage) {
        ScreenFloatWindowManager.shared.float(image)
    }

    func updateHotKey(_ newHotKey: AppHotKey) {
        guard newHotKey.hasPrimaryModifier else {
            lastErrorMessage = "Shortcut must include Command, Control, or Option."
            return
        }

        let previousHotKey = hotKey
        do {
            if isRunning {
                try hotKeyController.register(newHotKey, identifier: HotKeyID.captureFloatingScreenshot) { [weak self] in
                    self?.beginCapture()
                }
            }
            hotKey = newHotKey
            preferences.hotKey = newHotKey
            preferences.save()
            lastErrorMessage = nil
        } catch {
            if isRunning {
                try? hotKeyController.register(previousHotKey, identifier: HotKeyID.captureFloatingScreenshot) { [weak self] in
                    self?.beginCapture()
                }
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    func resetHotKey() {
        updateHotKey(.defaultScreenFloatValue)
    }

    private func registerHotKey() {
        do {
            try hotKeyController.register(hotKey, identifier: HotKeyID.captureFloatingScreenshot) { [weak self] in
                self?.beginCapture()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func completeCapture(_ image: NSImage) {
        ScreenFloatWindowManager.shared.float(image)
        ClipboardHistoryModule.shared.addImageToHistory(image)
        lastErrorMessage = nil
        cancelCapture(restoreFocus: true)
    }

    private func cancelCapture(restoreFocus: Bool) {
        selectionController?.close()
        selectionController = nil
        isCapturing = false
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
