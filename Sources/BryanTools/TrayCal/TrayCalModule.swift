import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class TrayCalModule: NSObject, ObservableObject, ToolModule, NSPopoverDelegate {
    static let shared = TrayCalModule()

    typealias ActionHandler = () -> Void

    let id = ToolIdentifier.trayCal
    let displayName = ToolIdentifier.trayCal.displayName
    let systemImage = "calendar"

    @Published private(set) var today: Date
    @Published private(set) var state: TrayCalCalendarState
    @Published private(set) var statusTitle: String

    private let calendar: Calendar
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var dateRefreshTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var workspaceNotificationTokens: [NSObjectProtocol] = []
    private var isRunning = false
    private var lastPopoverClosedAt: Date?
    private var showSettingsHandler: ActionHandler?
    private var quitHandler: ActionHandler?
    private var vehicleMotionCues = VehicleMotionCuesModule.shared

    private override init() {
        let calendar = TrayCalCalendar.defaultCalendar()
        let today = Date()
        self.calendar = calendar
        self.today = today
        self.state = TrayCalCalendarState(displayedMonth: today, calendar: calendar)
        self.statusTitle = TrayCalCalendar.statusTitle(for: today, calendar: calendar)
        super.init()
    }

    func setActionHandlers(showSettings: @escaping ActionHandler, quit: @escaping ActionHandler) {
        showSettingsHandler = showSettings
        quitHandler = quit
    }

    func setVehicleMotionCues(_ vehicleMotionCues: VehicleMotionCuesModule) {
        self.vehicleMotionCues = vehicleMotionCues
    }

    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        refreshDate()
        installStatusItem()
        installNotifications()
        scheduleDateRefreshTimer()
    }

    func stop() {
        isRunning = false
        closePopover()
        dateRefreshTimer?.invalidate()
        dateRefreshTimer = nil
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        for token in workspaceNotificationTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceNotificationTokens.removeAll()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    func menuContent() -> AnyView {
        AnyView(EmptyView())
    }

    func settingsView() -> AnyView {
        AnyView(EmptyView())
    }

    var monthTitle: String {
        TrayCalCalendar.monthTitle(for: state.displayedMonth, calendar: calendar)
    }

    var displayedMonthName: String {
        TrayCalCalendar.monthName(for: state.displayedMonth, calendar: calendar)
    }

    var displayedMonthNumber: Int {
        TrayCalCalendar.month(for: state.displayedMonth, calendar: calendar)
    }

    var displayedYear: Int {
        TrayCalCalendar.year(for: state.displayedMonth, calendar: calendar)
    }

    var monthSymbols: [String] {
        TrayCalCalendar.monthSymbols(calendar: calendar)
    }

    var calendarCells: [TrayCalDayCell] {
        TrayCalCalendar.monthGrid(
            displayedMonth: state.displayedMonth,
            today: today,
            calendar: calendar
        )
    }

    func showPreviousMonth() {
        state.showPreviousMonth(calendar: calendar)
    }

    func showNextMonth() {
        state.showNextMonth(calendar: calendar)
    }

    func returnToToday() {
        refreshDate()
        state.returnToToday(today, calendar: calendar)
    }

    func showMonth(_ month: Int) {
        state.showMonth(month, calendar: calendar)
    }

    func showYear(_ year: Int) {
        state.showYear(year, calendar: calendar)
    }

    func openSettings() {
        closePopover()
        showSettingsHandler?()
    }

    func quit() {
        quitHandler?()
    }

    func popoverDidClose(_ notification: Notification) {
        lastPopoverClosedAt = Date()
        statusItem?.button?.state = .off
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func installStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        guard let button = statusItem?.button else {
            return
        }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.title = statusTitle
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        button.toolTip = "TrayCal"
    }

    private func showPopover() {
        guard let button = statusItem?.button else {
            return
        }
        let popover = popover ?? makePopover()
        self.popover = popover
        refreshDate()
        resetDisplayedMonthIfNeeded(openingAt: today)
        button.title = statusTitle
        button.state = .on
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopover() {
        popover?.performClose(nil)
        statusItem?.button?.state = .off
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 248, height: 314)
        popover.delegate = self
        popover.contentViewController = NSHostingController(
            rootView: TrayCalPopoverView(environment: self, vehicleMotionCues: vehicleMotionCues)
        )
        return popover
    }

    private func installNotifications() {
        let dayChangedToken = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDateRefreshTrigger()
            }
        }
        notificationTokens.append(dayChangedToken)

        let activeToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDateRefreshTrigger()
            }
        }
        notificationTokens.append(activeToken)

        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDateRefreshTrigger()
            }
        }
        workspaceNotificationTokens.append(wakeToken)
    }

    private func handleDateRefreshTrigger() {
        refreshDate()
        scheduleDateRefreshTimer()
    }

    private func resetDisplayedMonthIfNeeded(openingAt openingDate: Date) {
        guard TrayCalCalendar.shouldResetPopoverAfterClose(
            closedAt: lastPopoverClosedAt,
            openingAt: openingDate
        ) else {
            return
        }
        state.returnToToday(openingDate, calendar: calendar)
        lastPopoverClosedAt = nil
    }

    private func refreshDate() {
        today = Date()
        statusTitle = TrayCalCalendar.statusTitle(for: today, calendar: calendar)
        statusItem?.button?.title = statusTitle
    }

    private func scheduleDateRefreshTimer() {
        dateRefreshTimer?.invalidate()
        let now = Date()
        let nextMidnight = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 0, minute: 0, second: 1),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(60 * 60)
        let interval = max(1, nextMidnight.timeIntervalSince(now))
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.handleDateRefreshTrigger()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        dateRefreshTimer = timer
    }
}
