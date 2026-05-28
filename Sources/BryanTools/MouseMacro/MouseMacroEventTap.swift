import ApplicationServices
import Foundation

@MainActor
final class MouseMacroEventTap {
    typealias ButtonHandler = (Int64) -> Bool

    private let handleButton: ButtonHandler
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handleButton: @escaping ButtonHandler) {
        self.handleButton = handleButton
    }

    func start() throws {
        guard eventTap == nil else {
            return
        }

        let mask = CGEventMask(1 << CGEventType.otherMouseDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw MouseMacroEventTapError.unableToCreateTap
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw MouseMacroEventTapError.unableToCreateTap
        }

        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        eventTap = nil
        runLoopSource = nil
    }

    private func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .otherMouseDown else {
            return Unmanaged.passUnretained(event)
        }

        let buttonNumber = event.getIntegerValueField(.mouseEventButtonNumber)
        return handleButton(buttonNumber) ? nil : Unmanaged.passUnretained(event)
    }

    private static let eventCallback: CGEventTapCallBack = { _, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let tap = Unmanaged<MouseMacroEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                tap.handle(event: event, type: type)
            }
        }

        var result: Unmanaged<CGEvent>?
        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                result = tap.handle(event: event, type: type)
            }
        }
        return result
    }
}

private enum MouseMacroEventTapError: Error, LocalizedError {
    case unableToCreateTap

    var errorDescription: String? {
        "Unable to start MouseMacro mouse listener. Enable Accessibility permission for Bryan Tools."
    }
}
