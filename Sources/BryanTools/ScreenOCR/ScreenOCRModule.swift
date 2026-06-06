import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class ScreenOCRModule: ObservableObject, ToolModule {
    static let shared = ScreenOCRModule(preferences: .load())

    typealias TextOutputHandler = (String) throws -> Void

    let id = ToolIdentifier.screenOCR
    let displayName = ToolIdentifier.screenOCR.displayName
    let systemImage = "text.viewfinder"

    @Published private(set) var hotKey: AppHotKey
    @Published private(set) var isCapturing = false
    @Published private(set) var isRecognizing = false
    @Published var lastErrorMessage: String?
    @Published var lastStatusMessage: String?

    private enum HotKeyID {
        static let captureText: HotKeyController.Identifier = 500
    }

    private let hotKeyController = HotKeyController()
    private var preferences: ScreenOCRPreferences
    private var selectionController: ScreenRegionSelectionController?
    private var isRunning = false
    private var appToRestoreFocus: NSRunningApplication?
    private var textOutputHandler: TextOutputHandler?
    private var recognitionTask: Task<Void, Never>?
    private var recognitionID = UUID()

    private init(preferences: ScreenOCRPreferences) {
        self.preferences = preferences
        self.hotKey = preferences.hotKey
    }

    func setTextOutputHandler(_ handler: @escaping TextOutputHandler) {
        textOutputHandler = handler
    }

    func start() {
        isRunning = true
        registerHotKey()
    }

    func stop() {
        isRunning = false
        cancelCapture(restoreFocus: false)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionID = UUID()
        isRecognizing = false
        hotKeyController.unregisterAll()
    }

    func menuContent() -> AnyView {
        AnyView(ScreenOCRMenuContent(environment: self))
    }

    func settingsView() -> AnyView {
        AnyView(ScreenOCRSettingsView(environment: self))
    }

    func beginCapture() {
        if isCapturing {
            cancelCapture(restoreFocus: true)
            return
        }
        guard !isRecognizing else {
            return
        }

        guard ColorPickerScreenCapture.ensurePermission(promptIfNeeded: true) else {
            lastErrorMessage = "Enable Screen Recording permission for Bryan Tools to OCR selected screen text."
            return
        }

        do {
            let captures = try ColorPickerScreenCapture.captureScreens()
            rememberAppForFocusRestore()
            let controller = ScreenRegionSelectionController(
                captures: captures,
                onSelection: { [weak self] selection in
                    self?.completeCapture(selection)
                },
                onCancel: { [weak self] in
                    self?.cancelCapture(restoreFocus: true)
                }
            )
            selectionController = controller
            isCapturing = true
            lastErrorMessage = nil
            lastStatusMessage = nil
            controller.show()
        } catch {
            lastErrorMessage = error.localizedDescription
            cancelCapture(restoreFocus: true)
        }
    }

    func updateHotKey(_ newHotKey: AppHotKey) {
        guard newHotKey.hasPrimaryModifier else {
            lastErrorMessage = "Shortcut must include Command, Control, or Option."
            return
        }

        let previousHotKey = hotKey
        do {
            if isRunning {
                try hotKeyController.register(newHotKey, identifier: HotKeyID.captureText) { [weak self] in
                    self?.beginCapture()
                }
            }
            hotKey = newHotKey
            preferences.hotKey = newHotKey
            preferences.save()
            lastErrorMessage = nil
        } catch {
            if isRunning {
                try? hotKeyController.register(previousHotKey, identifier: HotKeyID.captureText) { [weak self] in
                    self?.beginCapture()
                }
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    func resetHotKey() {
        updateHotKey(.defaultScreenOCRValue)
    }

    private func registerHotKey() {
        do {
            try hotKeyController.register(hotKey, identifier: HotKeyID.captureText) { [weak self] in
                self?.beginCapture()
            }
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    private func completeCapture(_ selection: ScreenRegionSelection) {
        cancelCapture(restoreFocus: true)
        recognitionTask?.cancel()
        let runID = UUID()
        recognitionID = runID
        isRecognizing = true
        lastStatusMessage = "Recognizing text..."
        lastErrorMessage = nil
        let image = selection.cgImage
        let moduleReference = WeakScreenOCRModule(self)

        recognitionTask = Task.detached(priority: .userInitiated) { [moduleReference, image, runID] in
            let result = Result {
                try ScreenOCRRecognizer.recognizeText(in: image)
            }
            let wasCancelled = Task.isCancelled

            await MainActor.run {
                moduleReference.value?.finishRecognition(result, runID: runID, wasCancelled: wasCancelled)
            }
        }
    }

    private func finishRecognition(_ result: Result<String, Error>, runID: UUID, wasCancelled: Bool) {
        guard recognitionID == runID,
              !wasCancelled else {
            return
        }

        do {
            let text = try result.get()
            try copyRecognizedText(text)
            lastStatusMessage = "Copied recognized text to clipboard."
            lastErrorMessage = nil
        } catch {
            lastStatusMessage = nil
            lastErrorMessage = error.localizedDescription
        }

        isRecognizing = false
        recognitionTask = nil
    }

    private func copyRecognizedText(_ text: String) throws {
        if let textOutputHandler {
            try textOutputHandler(text)
            return
        }

        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.setString(text, forType: .string) else {
            throw NSError(
                domain: "ScreenOCR",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to write OCR text to the pasteboard."]
            )
        }
        PasteboardChangeSuppressor.suppress(changeCount: NSPasteboard.general.changeCount)
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

private final class WeakScreenOCRModule: @unchecked Sendable {
    weak var value: ScreenOCRModule?

    init(_ value: ScreenOCRModule) {
        self.value = value
    }
}
