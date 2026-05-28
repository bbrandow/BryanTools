import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class DiskSpaceMonitorModule: NSObject, ObservableObject, ToolModule, NSPopoverDelegate {
    static let shared = DiskSpaceMonitorModule(preferences: .load())

    let id = ToolIdentifier.diskSpaceMonitor
    let displayName = ToolIdentifier.diskSpaceMonitor.displayName
    let systemImage = "internaldrive"

    @Published private(set) var isEnabled: Bool
    @Published private(set) var warningThresholdGB: Int
    @Published private(set) var visibleHistoryHours: Int?
    @Published private(set) var latestSample: DiskSpaceSample?
    @Published private(set) var samples: [DiskSpaceSample] = []
    @Published var lastErrorMessage: String?

    private var preferences: DiskSpaceMonitorPreferences
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var pollingTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var workspaceNotificationTokens: [NSObjectProtocol] = []
    private var store: DiskSpaceSampleStore?
    private var isRunning = false

    private init(preferences: DiskSpaceMonitorPreferences) {
        self.preferences = preferences
        self.isEnabled = preferences.isEnabled
        self.warningThresholdGB = preferences.warningThresholdGB
        self.visibleHistoryHours = preferences.visibleHistoryHours
        super.init()
    }

    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        if isEnabled {
            startMonitoring()
        }
    }

    func stop() {
        isRunning = false
        stopMonitoring()
    }

    func menuContent() -> AnyView {
        AnyView(EmptyView())
    }

    func settingsView() -> AnyView {
        AnyView(DiskSpaceMonitorSettingsView(environment: self))
    }

    var trayTitle: String {
        guard let latestSample else {
            return "--GB"
        }
        return DiskSpaceMonitorDisplay.trayTitle(availableBytes: latestSample.availableBytes)
    }

    var isBelowWarningThreshold: Bool {
        guard let latestSample else {
            return false
        }
        return DiskSpaceMonitorDisplay.isBelowWarningThreshold(
            availableBytes: latestSample.availableBytes,
            thresholdGB: warningThresholdGB
        )
    }

    var retentionStartDate: Date {
        Date().addingTimeInterval(-Double(DiskSpaceMonitorPreferences.retentionDays) * 24 * 60 * 60)
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
                startMonitoring()
            } else {
                stopMonitoring()
            }
        }
    }

    func updateWarningThresholdGB(_ value: Int) {
        let clamped = DiskSpaceMonitorPreferences.clampedWarningThresholdGB(value)
        guard clamped != warningThresholdGB else {
            return
        }
        warningThresholdGB = clamped
        preferences.warningThresholdGB = clamped
        preferences.save()
        updateStatusItem()
    }

    func updateVisibleHistoryHours(_ value: Int?) {
        let clamped = DiskSpaceMonitorPreferences.clampedVisibleHistoryHours(value)
        guard clamped != visibleHistoryHours else {
            return
        }
        visibleHistoryHours = clamped
        preferences.visibleHistoryHours = clamped
        preferences.save()
    }

    func measureNow() {
        guard isEnabled else {
            return
        }

        do {
            let store = try sampleStore()
            let sample = try DiskSpaceMeasurer.measurePrimaryVolume()
            try store.insert(sample)
            try store.purgeOlderThan()
            latestSample = sample
            samples = try store.samples(since: retentionStartDate)
            lastErrorMessage = nil
            updateStatusItem()
        } catch {
            lastErrorMessage = error.localizedDescription
            updateStatusItem()
        }
    }

    func reloadSamples() {
        do {
            let store = try sampleStore()
            latestSample = try store.latestSample()
            samples = try store.samples(since: retentionStartDate)
            updateStatusItem()
        } catch {
            lastErrorMessage = error.localizedDescription
        }
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

    private func startMonitoring() {
        installStatusItem()
        installNotifications()
        reloadSamples()
        measureNow()
        schedulePollingTimer()
    }

    private func stopMonitoring() {
        closePopover()
        pollingTimer?.invalidate()
        pollingTimer = nil
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

    private func installStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        guard let button = statusItem?.button else {
            return
        }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = tooltipText
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else {
            return
        }

        let color: NSColor = isBelowWarningThreshold ? .systemRed : .labelColor
        button.attributedTitle = NSAttributedString(
            string: trayTitle,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .semibold),
                .foregroundColor: color
            ]
        )
        button.toolTip = tooltipText
    }

    private var tooltipText: String {
        guard let latestSample else {
            return "Last measured: Not measured yet"
        }
        return "Last measured: \(Self.tooltipDateFormatter.string(from: latestSample.sampledAt))"
    }

    private func showPopover() {
        guard let button = statusItem?.button else {
            return
        }
        let popover = popover ?? makePopover()
        self.popover = popover
        reloadSamples()
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
        popover.contentSize = NSSize(width: 300, height: 238)
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: DiskSpaceMonitorPopoverView(environment: self))
        return popover
    }

    private func schedulePollingTimer() {
        pollingTimer?.invalidate()
        let timer = Timer(timeInterval: DiskSpaceMonitorPreferences.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.measureNow()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    private func installNotifications() {
        guard notificationTokens.isEmpty, workspaceNotificationTokens.isEmpty else {
            return
        }

        let activeToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIfStale()
            }
        }
        notificationTokens.append(activeToken)

        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshIfStale()
            }
        }
        workspaceNotificationTokens.append(wakeToken)
    }

    private func refreshIfStale() {
        guard isEnabled else {
            return
        }
        guard let latestSample else {
            measureNow()
            return
        }
        if Date().timeIntervalSince(latestSample.sampledAt) >= DiskSpaceMonitorPreferences.pollInterval {
            measureNow()
        }
    }

    private func sampleStore() throws -> DiskSpaceSampleStore {
        if let store {
            return store
        }
        let newStore = try DiskSpaceSampleStore()
        store = newStore
        return newStore
    }

    private static let tooltipDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
