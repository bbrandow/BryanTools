import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class AlarmModule: ObservableObject, ToolModule {
    static let shared = AlarmModule(preferences: .load())

    let id = ToolIdentifier.alarm
    let displayName = ToolIdentifier.alarm.displayName
    let systemImage = "alarm"

    @Published private(set) var state: AlarmState
    @Published private(set) var now = Date()
    @Published private(set) var showsFloatingTimer: Bool
    @Published var lastErrorMessage: String?

    private var preferences: AlarmPreferences
    private var fireTimer: Timer?
    private var displayTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var workspaceNotificationTokens: [NSObjectProtocol] = []
    private var isRunning = false

    private lazy var configurationPanelController = AlarmConfigurationPanelController(environment: self)
    private lazy var countdownWindowManager = AlarmCountdownWindowManager(
        onClick: { [weak self] in
            self?.showConfiguration()
        },
        onDismiss: { [weak self] in
            self?.updateFloatingTimerVisibility(false)
        },
        onPositionChange: { [weak self] position in
            self?.saveCountdownPosition(position)
        }
    )
    private let alertWindowManager = AlarmAlertWindowManager()

    private init(preferences: AlarmPreferences) {
        self.preferences = preferences
        self.state = AlarmState(targetDate: preferences.targetDate)
        self.showsFloatingTimer = preferences.showsFloatingTimer
    }

    var targetDate: Date? {
        state.targetDate
    }

    var isActive: Bool {
        state.isActive
    }

    var isFiring: Bool {
        state.phase == .firing
    }

    var remainingText: String {
        guard let targetDate else {
            return "00:00:00"
        }
        return AlarmSchedule.remainingText(target: targetDate, now: now)
    }

    var trayHelp: String {
        guard let targetDate else {
            return "Set alarm"
        }
        if isFiring {
            return "Alarm is due"
        }
        return "Alarm in \(AlarmSchedule.remainingText(target: targetDate, now: now))"
    }

    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        installNotifications()
        reconcile()
    }

    func stop() {
        isRunning = false
        invalidateTimers()
        removeNotifications()
        countdownWindowManager.close()
        alertWindowManager.close()
        configurationPanelController.close()
    }

    func menuContent() -> AnyView {
        AnyView(EmptyView())
    }

    func settingsView() -> AnyView {
        AnyView(EmptyView())
    }

    func showConfiguration() {
        now = Date()
        configurationPanelController.show()
    }

    func setAlarm(targetDate: Date) {
        let currentDate = Date()
        switch AlarmSchedule.validated(target: targetDate, now: currentDate) {
        case .success(let target):
            var newState = state
            newState.set(targetDate: target)
            state = newState
            now = currentDate
            preferences.targetDate = target
            preferences.showsFloatingTimer = true
            showsFloatingTimer = true
            preferences.save()
            lastErrorMessage = nil
            scheduleActiveAlarm()
            configurationPanelController.close()
        case .failure(let error):
            lastErrorMessage = error.localizedDescription
        }
    }

    func cancelAlarm() {
        clearAlarm()
    }

    func dismissAlarm() {
        clearAlarm()
    }

    func updateFloatingTimerVisibility(_ isVisible: Bool) {
        guard state.phase == .scheduled else {
            return
        }
        showsFloatingTimer = isVisible
        preferences.showsFloatingTimer = isVisible
        preferences.save()

        if isVisible, let targetDate {
            countdownWindowManager.show(
                text: AlarmSchedule.remainingText(target: targetDate, now: now),
                position: preferences.countdownPosition
            )
        } else {
            countdownWindowManager.close()
        }
    }

    private func reconcile(currentDate: Date = Date()) {
        now = currentDate
        switch AlarmSchedule.reconciliation(target: state.targetDate, now: currentDate) {
        case .none:
            invalidateTimers()
            countdownWindowManager.close()
            alertWindowManager.close()
        case .schedule:
            scheduleActiveAlarm()
        case .fireNow:
            fireAlarm()
        case .clear:
            clearAlarm()
        }
    }

    private func scheduleActiveAlarm() {
        guard isRunning, let targetDate = state.targetDate else {
            return
        }

        var scheduledState = state
        scheduledState.set(targetDate: targetDate)
        state = scheduledState
        alertWindowManager.close()
        scheduleFireTimer(targetDate: targetDate)
        scheduleDisplayTimer()
        if showsFloatingTimer {
            countdownWindowManager.show(
                text: AlarmSchedule.remainingText(target: targetDate, now: now),
                position: preferences.countdownPosition
            )
        } else {
            countdownWindowManager.close()
        }
    }

    private func fireAlarm() {
        guard isRunning, let targetDate = state.targetDate else {
            return
        }
        if state.phase == .firing {
            return
        }

        fireTimer?.invalidate()
        fireTimer = nil
        displayTimer?.invalidate()
        displayTimer = nil
        countdownWindowManager.close()

        var firingState = state
        firingState.markFiring()
        state = firingState
        alertWindowManager.show(targetDate: targetDate) { [weak self] in
            self?.dismissAlarm()
        }
    }

    private func clearAlarm() {
        invalidateTimers()
        var clearedState = state
        clearedState.clear()
        state = clearedState
        preferences.targetDate = nil
        preferences.showsFloatingTimer = true
        showsFloatingTimer = true
        preferences.save()
        lastErrorMessage = nil
        countdownWindowManager.close()
        alertWindowManager.close()
    }

    private func scheduleFireTimer(targetDate: Date) {
        fireTimer?.invalidate()
        let interval = max(0.05, targetDate.timeIntervalSinceNow)
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        fireTimer = timer
    }

    private func scheduleDisplayTimer() {
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshCountdown()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        displayTimer = timer
    }

    private func refreshCountdown() {
        guard let targetDate = state.targetDate, state.phase == .scheduled else {
            return
        }
        now = Date()
        if targetDate <= now {
            fireAlarm()
            return
        }
        if showsFloatingTimer {
            countdownWindowManager.show(
                text: AlarmSchedule.remainingText(target: targetDate, now: now),
                position: preferences.countdownPosition
            )
        }
    }

    private func invalidateTimers() {
        fireTimer?.invalidate()
        fireTimer = nil
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func saveCountdownPosition(_ position: AlarmPanelPosition) {
        preferences.countdownPosition = position
        preferences.save()
    }

    private func installNotifications() {
        guard notificationTokens.isEmpty, workspaceNotificationTokens.isEmpty else {
            return
        }

        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange,
            NSApplication.didBecomeActiveNotification
        ]
        notificationTokens = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: name == NSApplication.didBecomeActiveNotification ? NSApp : nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.reconcile()
                }
            }
        }

        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reconcile()
            }
        }
        workspaceNotificationTokens.append(wakeToken)
    }

    private func removeNotifications() {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        for token in workspaceNotificationTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceNotificationTokens.removeAll()
    }
}
