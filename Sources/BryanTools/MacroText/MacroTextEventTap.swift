import AppKit
import Carbon
import CoreGraphics
import Foundation

final class MacroTextEventTap {
    private var replacements: [MacroTextReplacement]
    private let onMatch: (MacroTextReplacement) -> Void
    private let onError: (String) -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var buffer = ""
    private var isExpanding = false

    init(
        replacements: [MacroTextReplacement],
        onMatch: @escaping (MacroTextReplacement) -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.replacements = replacements
        self.onMatch = onMatch
        self.onError = onError
    }

    func start() throws {
        stop()

        let eventMask = (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: MacroTextEventTap.eventCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw MacroTextEventTapError.unableToCreateTap
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            throw MacroTextEventTapError.unableToCreateTap
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
        buffer = ""
    }

    func updateReplacements(_ replacements: [MacroTextReplacement]) {
        self.replacements = replacements
        buffer = ""
    }

    func suppressEventsForExpansion() {
        isExpanding = true
        buffer = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.isExpanding = false
        }
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        processKeyDown(event)
        return Unmanaged.passUnretained(event)
    }

    private func processKeyDown(_ event: CGEvent) {
        guard !isExpanding else {
            return
        }

        let flags = event.flags
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            buffer = ""
            return
        }

        let keyCode = Int(event.getIntegerValueField(.keyboardEventKeycode))
        switch keyCode {
        case kVK_Delete:
            if !buffer.isEmpty {
                buffer.removeLast()
            }
            return
        case kVK_Return, kVK_Tab, kVK_Escape:
            buffer = ""
            return
        default:
            break
        }

        guard let text = unicodeString(from: event), !text.isEmpty else {
            return
        }

        if text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil {
            buffer = ""
            return
        }

        buffer += text
        if buffer.count > 128 {
            buffer = String(buffer.suffix(128))
        }

        guard let match = longestMatchingReplacement() else {
            return
        }

        suppressEventsForExpansion()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [onMatch] in
            onMatch(match)
        }
    }

    private func longestMatchingReplacement() -> MacroTextReplacement? {
        replacements
            .filter { !$0.command.isEmpty && buffer.hasSuffix($0.command) }
            .max { $0.command.count < $1.command.count }
    }

    private func unicodeString(from event: CGEvent) -> String? {
        var length = 0
        var chars = [UniChar](repeating: 0, count: 8)
        event.keyboardGetUnicodeString(
            maxStringLength: chars.count,
            actualStringLength: &length,
            unicodeString: &chars
        )
        guard length > 0 else {
            return nil
        }
        return String(utf16CodeUnits: chars, count: length)
    }

    private static let eventCallback: CGEventTapCallBack = { proxy, type, event, userInfo in
        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }
        let listener = Unmanaged<MacroTextEventTap>.fromOpaque(userInfo).takeUnretainedValue()
        return listener.handle(proxy: proxy, type: type, event: event)
    }
}

private enum MacroTextEventTapError: Error, LocalizedError {
    case unableToCreateTap

    var errorDescription: String? {
        "Unable to start MacroText keyboard listener. Enable Accessibility permission for Bryan Tools."
    }
}
