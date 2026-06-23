import AppKit
import BryanToolsShared
import Foundation
import SwiftUI

@MainActor
final class VehicleMotionCuesModule: NSObject, ObservableObject, ToolModule {
    static let shared = VehicleMotionCuesModule(
        controller: SystemVehicleMotionCuesController(),
        preferences: .load()
    )

    let id = ToolIdentifier.vehicleMotionCues
    let displayName = ToolIdentifier.vehicleMotionCues.displayName
    let systemImage = "car.side"

    @Published private(set) var isTrayEnabled: Bool
    @Published private(set) var snapshot = VehicleMotionCuesSnapshot(isSupported: true, isEnabled: false, isActive: false)
    @Published var lastErrorMessage: String?

    private let controller: SystemVehicleMotionCuesController
    private var preferences: VehicleMotionCuesPreferences
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var notificationTokens: [NSObjectProtocol] = []
    private var isRunning = false
    private var isObservingDarwinPreferenceChanges = false

    private init(controller: SystemVehicleMotionCuesController, preferences: VehicleMotionCuesPreferences) {
        self.controller = controller
        self.preferences = preferences
        self.isTrayEnabled = preferences.isTrayEnabled
        super.init()
    }

    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        if isTrayEnabled {
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

    func updateTrayEnabled(_ enabled: Bool) {
        guard enabled != isTrayEnabled else {
            return
        }
        isTrayEnabled = enabled
        preferences.isTrayEnabled = enabled
        preferences.save()

        if isRunning {
            if enabled {
                startShowing()
            } else {
                stopShowing()
            }
        }
    }

    func refresh() {
        refresh(reconcileRuntime: false)
    }

    private func refresh(reconcileRuntime: Bool) {
        do {
            snapshot = try controller.snapshot(reconcileActiveState: reconcileRuntime)
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        updateStatusItem()
    }

    @objc private func toggleEnabled(_ sender: Any?) {
        do {
            snapshot = try controller.toggleEnabled()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
        updateStatusItem()
    }

    private func startShowing() {
        installStatusItem()
        installNotifications()
        refresh(reconcileRuntime: true)
        scheduleRefreshTimer()
    }

    private func stopShowing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        removeNotifications()
        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        statusItem = nil
    }

    private func installStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        }
        guard let button = statusItem?.button else {
            return
        }
        button.target = self
        button.action = #selector(toggleEnabled(_:))
        button.imagePosition = .imageOnly
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else {
            return
        }
        let imageName = VehicleMotionCuesDisplay.systemImageName(for: snapshot)
        let image = NSImage(systemSymbolName: imageName, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "car", accessibilityDescription: nil)
        image?.isTemplate = true
        button.image = image
        button.contentTintColor = tintColor
        button.toolTip = lastErrorMessage ?? VehicleMotionCuesDisplay.tooltip(for: snapshot)
        button.setAccessibilityLabel(lastErrorMessage ?? VehicleMotionCuesDisplay.accessibilityLabel(for: snapshot))
        button.isEnabled = snapshot.isSupported || lastErrorMessage != nil
    }

    private var tintColor: NSColor {
        if lastErrorMessage != nil || !snapshot.isSupported {
            return .systemRed
        }
        return snapshot.isOn ? .controlAccentColor : .secondaryLabelColor
    }

    private func scheduleRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
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

        let appToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reconcileRuntime: false)
            }
        }

        let wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh(reconcileRuntime: true)
            }
        }

        notificationTokens = [appToken, wakeToken]
        installDarwinPreferenceObserver()
    }

    private func removeNotifications() {
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        notificationTokens.removeAll()

        if isObservingDarwinPreferenceChanges {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                Unmanaged.passUnretained(self).toOpaque(),
                CFNotificationName(rawValue: SystemVehicleMotionCuesController.preferenceDidChangeNotificationName as CFString),
                nil
            )
            isObservingDarwinPreferenceChanges = false
        }
    }

    private func installDarwinPreferenceObserver() {
        guard !isObservingDarwinPreferenceChanges else {
            return
        }
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else {
                    return
                }
                let module = Unmanaged<VehicleMotionCuesModule>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    module.refresh(reconcileRuntime: true)
                }
            },
            SystemVehicleMotionCuesController.preferenceDidChangeNotificationName as CFString,
            nil,
            .deliverImmediately
        )
        isObservingDarwinPreferenceChanges = true
    }
}
