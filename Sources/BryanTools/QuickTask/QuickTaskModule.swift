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
    static let applicationRowHeight = CGFloat(60)
    static let calculationRowHeight = CGFloat(100)
    static let applicationResultBottomPadding = CGFloat(52)
    static let calculationResultBottomPadding = CGFloat(20)
    static let minimumApplicationResultRows = 3

    let id = ToolIdentifier.quickTask
    let displayName = ToolIdentifier.quickTask.displayName
    let systemImage = "command"
    private static let retainedDismissalInterval: TimeInterval = 120

    @Published private(set) var hotKey: AppHotKey
    @Published var query = "" {
        didSet {
            formatQueryIfNeeded()
            updateResults()
        }
    }
    @Published private(set) var applications: [QuickTaskApplication] = []
    @Published private(set) var matches: [QuickTaskApplication] = []
    @Published private(set) var calculationResult: String?
    @Published private(set) var focusRequestID = 0
    @Published var lastErrorMessage: String?

    var panelSize: NSSize {
        if resultContentHeight > 0 {
            return NSSize(
                width: Self.barOnlyPanelSize.width,
                height: Self.barOnlyPanelSize.height + 1 + resultContentHeight
            )
        }
        return Self.barOnlyPanelSize
    }

    var resultContentHeight: CGFloat {
        if calculationResult != nil {
            return Self.calculationRowHeight + Self.calculationResultBottomPadding
        }
        guard !matches.isEmpty else {
            return 0
        }
        let visibleRows = min(max(matches.count, Self.minimumApplicationResultRows), 6)
        let dividerHeight = CGFloat(max(matches.count - 1, 0))
        return CGFloat(visibleRows) * Self.applicationRowHeight
            + dividerHeight
            + Self.applicationResultBottomPadding
    }

    var resultBottomPadding: CGFloat {
        calculationResult != nil
            ? Self.calculationResultBottomPadding
            : Self.applicationResultBottomPadding
    }

    private enum HotKeyID {
        static let openQuickTask: HotKeyController.Identifier = 300
    }

    private let hotKeyController = HotKeyController()
    private var preferences: QuickTaskPreferences
    private var isRunning = false
    private var isFormattingQuery = false
    private var retainedQueryClearWorkItem: DispatchWorkItem?
    private var retainedQueryExpiresAt: Date?
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
        clearExpiredRetainedQueryIfNeeded()
        cancelRetainedQueryClear()
        applications = QuickTaskApplicationIndex.loadApplications()
        updateResults()
        panelController.show()
        requestInputFocus()
    }

    func toggleQuickTask() {
        if panelController.isVisible {
            dismissQuickTask()
        } else {
            showQuickTask()
        }
    }

    func closeQuickTask() {
        cancelRetainedQueryClear()
        query = ""
        panelController.close()
    }

    func dismissQuickTask() {
        scheduleRetainedQueryClearIfNeeded()
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
            copyCalculationResultToClipboard()
            closeQuickTask()
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
                    self?.toggleQuickTask()
                }
            }
            hotKey = newHotKey
            preferences.hotKey = newHotKey
            preferences.save()
            lastErrorMessage = nil
        } catch {
            if isRunning {
                try? hotKeyController.register(previousHotKey, identifier: HotKeyID.openQuickTask) { [weak self] in
                    self?.toggleQuickTask()
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

    private func requestInputFocus() {
        focusRequestID += 1
    }

    private func formatQueryIfNeeded() {
        guard !isFormattingQuery else {
            return
        }

        let formattedQuery = QuickTaskCalculator.formattedExpression(query)
        guard formattedQuery != query else {
            return
        }

        isFormattingQuery = true
        query = formattedQuery
        isFormattingQuery = false
    }

    private func copyCalculationResultToClipboard() {
        guard let calculationResult else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(calculationResult, forType: .string)
    }

    private func scheduleRetainedQueryClearIfNeeded() {
        cancelRetainedQueryClear()
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            retainedQueryExpiresAt = nil
            return
        }

        let expirationDate = Date().addingTimeInterval(Self.retainedDismissalInterval)
        retainedQueryExpiresAt = expirationDate
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                guard let self,
                      self.retainedQueryExpiresAt == expirationDate,
                      !self.panelController.isVisible else {
                    return
                }
                self.query = ""
                self.retainedQueryExpiresAt = nil
                self.retainedQueryClearWorkItem = nil
            }
        }
        retainedQueryClearWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.retainedDismissalInterval, execute: workItem)
    }

    private func cancelRetainedQueryClear() {
        retainedQueryClearWorkItem?.cancel()
        retainedQueryClearWorkItem = nil
        retainedQueryExpiresAt = nil
    }

    private func clearExpiredRetainedQueryIfNeeded() {
        guard let retainedQueryExpiresAt,
              Date() >= retainedQueryExpiresAt else {
            return
        }
        query = ""
        cancelRetainedQueryClear()
    }

    private func registerHotKeyWithFallback() {
        do {
            try hotKeyController.register(hotKey, identifier: HotKeyID.openQuickTask) { [weak self] in
                self?.toggleQuickTask()
            }
            lastErrorMessage = nil
        } catch {
            guard hotKey == .defaultQuickTaskValue else {
                lastErrorMessage = error.localizedDescription
                return
            }
            do {
                try hotKeyController.register(.fallbackQuickTaskValue, identifier: HotKeyID.openQuickTask) { [weak self] in
                    self?.toggleQuickTask()
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
