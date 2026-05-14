import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class QuickTaskModule: ObservableObject, ToolModule {
    static let shared = QuickTaskModule(preferences: .load())
    static let barOnlyPanelSize = NSSize(width: 760, height: 76)
    static let minimumPanelSize = NSSize(width: 520, height: 76)
    static let maximumPanelSize = NSSize(width: 1_100, height: 560)
    static let applicationRowHeight = CGFloat(56)
    static let calculationRowHeight = CGFloat(100)
    static let resultBottomPadding = CGFloat(14)

    let id = ToolIdentifier.quickTask
    let displayName = ToolIdentifier.quickTask.displayName
    let systemImage = "command"

    @Published private(set) var hotKey: AppHotKey
    @Published var query = "" {
        didSet {
            updateResults()
        }
    }
    @Published private(set) var applications: [QuickTaskApplication] = []
    @Published private(set) var matches: [QuickTaskApplication] = []
    @Published private(set) var calculationResult: String?
    @Published var lastErrorMessage: String?

    var panelSize: NSSize {
        if calculationResult != nil || !matches.isEmpty {
            let resultHeight = calculationResult != nil
                ? Self.calculationRowHeight
                : CGFloat(min(matches.count, 6)) * Self.applicationRowHeight
            return NSSize(
                width: Self.barOnlyPanelSize.width,
                height: Self.barOnlyPanelSize.height + 1 + resultHeight + Self.resultBottomPadding
            )
        }
        return Self.barOnlyPanelSize
    }

    private enum HotKeyID {
        static let openQuickTask: HotKeyController.Identifier = 300
    }

    private let hotKeyController = HotKeyController()
    private var preferences: QuickTaskPreferences
    private var isRunning = false
    private lazy var panelController = QuickTaskPanelController(environment: self)

    private init(preferences: QuickTaskPreferences) {
        self.preferences = preferences
        self.hotKey = preferences.hotKey
        self.applications = QuickTaskApplicationIndex.loadApplications()
        updateResults()
    }

    func start() {
        isRunning = true
        registerHotKeyWithFallback()
    }

    func stop() {
        isRunning = false
        hotKeyController.unregisterAll()
        panelController.close()
    }

    func menuContent() -> AnyView {
        AnyView(QuickTaskMenuContent(environment: self))
    }

    func settingsView() -> AnyView {
        AnyView(QuickTaskSettingsView(environment: self))
    }

    func showQuickTask() {
        applications = QuickTaskApplicationIndex.loadApplications()
        updateResults()
        panelController.show()
    }

    func closeQuickTask() {
        query = ""
        panelController.close()
    }

    func launch(_ application: QuickTaskApplication) {
        NSWorkspace.shared.openApplication(at: application.url, configuration: NSWorkspace.OpenConfiguration())
        closeQuickTask()
    }

    func submitQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            closeQuickTask()
            return
        }

        if calculationResult != nil {
            return
        }

        if let application = matches.first {
            launch(application)
            return
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
                try hotKeyController.register(newHotKey, identifier: HotKeyID.openQuickTask) { [weak self] in
                    self?.showQuickTask()
                }
            }
            hotKey = newHotKey
            preferences.hotKey = newHotKey
            preferences.save()
            lastErrorMessage = nil
        } catch {
            if isRunning {
                try? hotKeyController.register(previousHotKey, identifier: HotKeyID.openQuickTask) { [weak self] in
                    self?.showQuickTask()
                }
            }
            lastErrorMessage = error.localizedDescription
        }
    }

    func resetHotKey() {
        updateHotKey(.defaultQuickTaskValue)
    }

    private func updateResults() {
        matches = QuickTaskApplicationIndex.matches(for: query, applications: applications)
        if let value = QuickTaskCalculator.evaluate(query) {
            calculationResult = QuickTaskCalculator.formatted(value)
        } else {
            calculationResult = nil
        }
        panelController.updateSize()
    }

    private func registerHotKeyWithFallback() {
        do {
            try hotKeyController.register(hotKey, identifier: HotKeyID.openQuickTask) { [weak self] in
                self?.showQuickTask()
            }
            lastErrorMessage = nil
        } catch {
            guard hotKey == .defaultQuickTaskValue else {
                lastErrorMessage = error.localizedDescription
                return
            }
            do {
                try hotKeyController.register(.fallbackQuickTaskValue, identifier: HotKeyID.openQuickTask) { [weak self] in
                    self?.showQuickTask()
                }
                hotKey = .fallbackQuickTaskValue
                preferences.hotKey = .fallbackQuickTaskValue
                preferences.save()
                lastErrorMessage = "Command-Space was unavailable. QuickTask is using Option-Space."
            } catch {
                lastErrorMessage = error.localizedDescription
            }
        }
    }
}
