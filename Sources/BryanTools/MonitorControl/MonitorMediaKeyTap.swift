import AppKit
import MonitorControlCore

@MainActor
final class MonitorMediaKeyTap {
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private let handle: (MonitorKeyEvent, NSEvent.ModifierFlags) -> Bool

    init(handle: @escaping (MonitorKeyEvent, NSEvent.ModifierFlags) -> Bool) { self.handle = handle }

    func start() -> Bool {
        guard port == nil else { return true }
        let mask = (CGEventMask(1) << NSEvent.EventType.systemDefined.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                          eventsOfInterest: mask, callback: Self.callback,
                                          userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            CFMachPortInvalidate(port)
            return false
        }
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return true
    }

    func stop() {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
        source = nil
        port = nil
    }

    private func process(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        let key: MonitorKeyEvent?
        if type == .keyDown || type == .keyUp {
            key = MonitorKeyEvent(brightnessKeyCode: event.getIntegerValueField(.keyboardEventKeycode),
                                  isDown: type == .keyDown, isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        } else if type.rawValue == NSEvent.EventType.systemDefined.rawValue, let native = NSEvent(cgEvent: event) {
            key = MonitorKeyEvent(subtype: native.subtype.rawValue, data1: native.data1)
        } else { key = nil }
        guard let key else { return Unmanaged.passUnretained(event) }
        let modifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
        return handle(key, modifiers) ? nil : Unmanaged.passUnretained(event)
    }

    private static let callback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else { return Unmanaged.passUnretained(event) }
        // This tap's source is installed exclusively on the main run loop. No hardware I/O here.
        return MainActor.assumeIsolated {
            Unmanaged<MonitorMediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue().process(event, type: type)
        }
    }
}
