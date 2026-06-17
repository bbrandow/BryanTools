import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class UTCHourModule: NSObject, ObservableObject, ToolModule, NSPopoverDelegate {
    static let shared = UTCHourModule(preferences: .load())

    let id = ToolIdentifier.utcHour
    let displayName = ToolIdentifier.utcHour.displayName
    let systemImage = "clock"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var currentHour: Date
    @Published private(set) var lookupRows: [UTCHourRow]
    @Published var lastErrorMessage: String?

    private var preferences: UTCHourPreferences
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var refreshTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var isRunning = false

    private init(preferences: UTCHourPreferences) {
        self.preferences = preferences
        self.isEnabled = preferences.isEnabled
        let now = Date()
        self.currentHour = UTCHourDisplay.currentUTCHour(now: now)
        self.lookupRows = UTCHourDisplay.lookupRows(centeredAt: now)
        super.init()
    }

    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        if isEnabled {
            startShowing()
        }
    }

    func stop() {
        isRunning = false
        stopShowing()
    }

    func menuContent() -> AnyView {
        AnyView(EmptyView())
    }

    func settingsView() -> AnyView {
        AnyView(EmptyView())
    }

    var trayTitle: String {
        UTCHourDisplay.statusTitle(for: currentHour)
    }

    func updateEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else {
            return
        }
        isEnabled = enabled
        preferences.isEnabled = enabled
        preferences.save()

        if isRunning {
            if enabled {
                startShowing()
            } else {
                stopShowing()
            }
        }
    }

    func refresh(now: Date = Date()) {
        currentHour = UTCHourDisplay.currentUTCHour(now: now)
        lookupRows = UTCHourDisplay.lookupRows(centeredAt: now)
        updateStatusItem()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem?.button?.state = .off
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover?.isShown == true {
            closePopover()
        } else {
            showPopover()
        }
    }

    private func startShowing() {
        installStatusItem()
        installNotifications()
        refresh()
        scheduleRefreshTimer()
    }

    private func stopShowing() {
        closePopover()
        refreshTimer?.invalidate()
        refreshTimer = nil
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
        }
        notificationTokens.removeAll()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
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
        button.toolTip = "UTC Hour"
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else {
            return
        }
        button.attributedTitle = NSAttributedString(
            string: trayTitle,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: NSColor.labelColor
            ]
        )
        button.toolTip = "UTC hour: \(trayTitle)"
    }

    private func showPopover() {
        guard let button = statusItem?.button else {
            return
        }
        let popover = popover ?? makePopover()
        self.popover = popover
        refresh()
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
        popover.contentSize = NSSize(width: 410, height: 420)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: UTCHourPopoverView(environment: self))
        return popover
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func installNotifications() {
        guard notificationTokens.isEmpty else {
            return
        }

        let names: [Notification.Name] = [
            .NSCalendarDayChanged,
            .NSSystemClockDidChange,
            .NSSystemTimeZoneDidChange
        ]

        notificationTokens = names.map { name in
            NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.refresh()
                }
            }
        }
    }
}
