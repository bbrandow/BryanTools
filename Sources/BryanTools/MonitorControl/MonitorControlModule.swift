import AppKit
import BryanToolsShared
import MonitorControlCore
import os
import SwiftUI

@MainActor
final class MonitorControlModule: ToolModule {
    static let shared = MonitorControlModule()
    let id = ToolIdentifier.monitorControl
    let displayName = ToolIdentifier.monitorControl.displayName
    let systemImage = "display"

    private let worker = MonitorHardwareWorker()
    private let audioObserver = MonitorAudioOutputObserver()
    private let log = Logger(subsystem: "com.local.BryanTools", category: "MonitorControl")
    private var tap: MonitorMediaKeyTap?
    private var keyTracker = MonitorKeyTracker()
    private var generation: UInt64 = 0
    private var levels: MonitorHardwareWorker.Levels = [:]
    private var suspendedLevels: MonitorHardwareWorker.Levels = [:]
    private var displays: [MonitorDescriptor] = []
    private var audio: MonitorAudioOutput?
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var refreshTask: DispatchWorkItem?
    private var isRunning = false
    private var isSleeping = false
    private var lastRefresh = Date.distantPast

    func menuContent() -> AnyView { AnyView(EmptyView()) }
    func settingsView() -> AnyView { AnyView(EmptyView()) }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        audioObserver.start { [weak self] output in self?.audio = output }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.scheduleRefresh() }
        observe(.default, NSApplication.didBecomeActiveNotification) {
            $0.startTapIfNeeded()
            if $0.levels.isEmpty, Date().timeIntervalSince($0.lastRefresh) > 30 { $0.scheduleRefresh() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { module in
            module.isSleeping = true
            module.suspend()
        }
        observe(workspace, NSWorkspace.didWakeNotification) { module in
            module.isSleeping = false
            module.audioObserver.refresh()
            module.scheduleRefresh()
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.startTapIfNeeded() }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            let observer = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated {
                    guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                          app.bundleIdentifier == Self.monitorControlBundleID else { return }
                    self?.scheduleRefresh()
                }
            }
            observers.append((workspace, observer))
        }
        refresh()
    }

    func stop() {
        isRunning = false
        suspend()
        audioObserver.stop()
        for (center, observer) in observers { center.removeObserver(observer) }
        observers.removeAll()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name,
                         action: @escaping (MonitorControlModule) -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { action(self) } }
        }
        observers.append((center, observer))
    }

    private func suspend() {
        refreshTask?.cancel()
        refreshTask = nil
        tap?.stop()
        tap = nil
        keyTracker = MonitorKeyTracker()
        if !levels.isEmpty { suspendedLevels = levels }
        levels.removeAll()
        worker.stop()
    }

    private func scheduleRefresh() {
        suspend()
        guard isRunning, !isSleeping else { return }
        let task = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: task)
    }

    private func refresh() {
        guard isRunning, !isSleeping, !Self.otherControllerRunning else { return }
        lastRefresh = Date()
        displays = Self.connectedDisplays()
        generation = worker.refresh(displays) { [weak self] token, levels in
            guard let self, self.isRunning, !self.isSleeping else { return }
            self.generation = token
            self.levels = levels
            for (address, reading) in levels {
                if let previous = self.suspendedLevels[address] {
                    self.levels[address] = previous.refreshed(with: reading)
                }
            }
            self.suspendedLevels.removeAll()
            self.log.info("Detected \(levels.count) supported external monitor controls")
            self.startTapIfNeeded()
        }
    }

    private func startTapIfNeeded() {
        guard isRunning, !isSleeping, tap == nil, !levels.isEmpty, !Self.otherControllerRunning else { return }
        guard AccessibilityPermissionService.ensurePermission(promptIfNeeded: true) else { return }
        let tap = MonitorMediaKeyTap { [weak self] event, flags in self?.handle(event, flags: flags) ?? false }
        if tap.start() { self.tap = tap }
        else { log.error("Could not start external monitor keyboard listener; check Accessibility permission") }
    }

    private func handle(_ event: MonitorKeyEvent, flags: NSEvent.ModifierFlags) -> Bool {
        let fine = flags.contains([.option, .shift])
        // Preserve macOS Option-key preference shortcuts and Control/Command combinations.
        let reserved = flags.contains(.command) || flags.contains(.control) || (flags.contains(.option) && !fine)
        var targets: [UInt32] = []
        if !reserved {
            let supported = Set(levels.keys.filter { $0.feature == event.key.feature }.map(\.display))
            if event.key.feature == .brightness {
                let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
                let displayID = (screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
                targets = MonitorRouting.brightness(displays: displays, pointerDisplay: displayID, supported: supported)
            } else if let audio, let target = MonitorRouting.volume(displays: displays, audioName: audio.name,
                                                                    isDisplayAudio: audio.isDisplayAudio,
                                                                    hasNativeVolume: audio.hasNativeVolume, supported: supported) {
                targets = [target]
            }
        }
        let route = keyTracker.handle(event, candidates: targets)
        for target in route.targets where targets.contains(target) {
            let address = MonitorControlAddress(display: target, feature: event.key.feature)
            guard var level = levels[address] else { continue }
            let previous = level.current
            level.apply(event.key, fine: fine)
            levels[address] = level
            guard level.current != previous else { continue }
            worker.set(address, value: level.current, generation: generation) { [weak self] address in
                self?.levels.removeValue(forKey: address)
                self?.log.error("Monitor write failed for display \(address.display), control \(address.feature.rawValue); leaving subsequent keys to macOS")
            }
        }
        return route.consume
    }

    private static let monitorControlBundleID = "app.monitorcontrol.MonitorControl"
    private static var otherControllerRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: monitorControlBundleID).isEmpty
    }

    private static func connectedDisplays() -> [MonitorDescriptor] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let names = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (UInt32, String)? in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            return (number.uint32Value, screen.localizedName)
        })
        return ids.prefix(Int(count)).map {
            MonitorDescriptor(id: $0, name: names[$0] ?? "", isBuiltIn: CGDisplayIsBuiltin($0) != 0,
                              mirrorSource: CGDisplayMirrorsDisplay($0))
        }
    }
}
