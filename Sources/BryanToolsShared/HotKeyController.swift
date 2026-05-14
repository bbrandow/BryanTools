import Carbon
import Foundation

@MainActor
public final class HotKeyController {
    public typealias Identifier = UInt32

    public enum Trigger {
        case pressed
        case released

        func matches(eventKind: UInt32) -> Bool {
            switch self {
            case .pressed:
                return eventKind == UInt32(kEventHotKeyPressed)
            case .released:
                return eventKind == UInt32(kEventHotKeyReleased)
            }
        }
    }

    private struct Registration {
        let ref: EventHotKeyRef
        let trigger: Trigger
        let action: () -> Void
    }

    private let signature = HotKeyController.fourCharCode("BRYN")
    private var eventHandlerRef: EventHandlerRef?
    private var registrations: [Identifier: Registration] = [:]

    public init() {}

    public func register(
        _ hotKey: AppHotKey,
        identifier: Identifier,
        trigger: Trigger = .pressed,
        action: @escaping () -> Void
    ) throws {
        unregister(identifier: identifier)
        try installEventHandlerIfNeeded()

        var hotKeyRef: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: identifier)
        let registerStatus = RegisterEventHotKey(
            hotKey.keyCode,
            hotKey.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registerStatus == noErr, let hotKeyRef else {
            throw BryanToolsError.hotKey("Unable to register \(hotKey.displayString) hotkey: \(registerStatus)")
        }

        registrations[identifier] = Registration(ref: hotKeyRef, trigger: trigger, action: action)
    }

    public func unregister(identifier: Identifier) {
        guard let registration = registrations.removeValue(forKey: identifier) else {
            return
        }
        UnregisterEventHotKey(registration.ref)
    }

    public func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.ref)
        }
        registrations.removeAll()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    private func performAction(for hotKeyID: EventHotKeyID?, eventKind: UInt32) -> OSStatus {
        guard let hotKeyID,
              hotKeyID.signature == signature,
              let registration = registrations[hotKeyID.id] else {
            return OSStatus(eventNotHandledErr)
        }

        guard registration.trigger.matches(eventKind: eventKind) else {
            return noErr
        }

        registration.action()
        return noErr
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else {
            return
        }

        let eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            ),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)
            )
        ]

        let installStatus = eventTypes.withUnsafeBufferPointer { buffer in
            InstallEventHandler(
                GetApplicationEventTarget(),
                HotKeyController.hotKeyHandler,
                buffer.count,
                buffer.baseAddress,
                Unmanaged.passUnretained(self).toOpaque(),
                &eventHandlerRef
            )
        }
        guard installStatus == noErr else {
            throw BryanToolsError.hotKey("Unable to install hotkey handler: \(installStatus)")
        }
    }

    private static let hotKeyHandler: EventHandlerUPP = { _, event, userData in
        guard let userData else {
            return OSStatus(eventNotHandledErr)
        }

        let hotKeyID = eventHotKeyID(from: event)
        let eventKind = event.map { UInt32(GetEventKind($0)) } ?? 0
        let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()

        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                controller.performAction(for: hotKeyID, eventKind: eventKind)
            }
        }

        var status = OSStatus(eventNotHandledErr)
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                status = controller.performAction(for: hotKeyID, eventKind: eventKind)
            }
        }
        return status
    }

    private static func eventHotKeyID(from event: EventRef?) -> EventHotKeyID? {
        guard let event else {
            return nil
        }

        var hotKeyID = EventHotKeyID()
        let status = withUnsafeMutablePointer(to: &hotKeyID) { pointer in
            GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                pointer
            )
        }

        return status == noErr ? hotKeyID : nil
    }

    private static func fourCharCode(_ string: String) -> OSType {
        var result: OSType = 0
        for scalar in string.unicodeScalars.prefix(4) {
            result = (result << 8) + OSType(scalar.value)
        }
        return result
    }
}
