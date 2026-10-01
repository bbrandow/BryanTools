import Foundation

public enum MonitorFeature: UInt8, Hashable { case brightness = 0x10, volume = 0x62 }

public enum MonitorMediaKey: Int, Hashable {
    case volumeUp = 0, volumeDown = 1, brightnessUp = 2, brightnessDown = 3, mute = 7

    public var feature: MonitorFeature {
        self == .brightnessUp || self == .brightnessDown ? .brightness : .volume
    }

    public var isUp: Bool { self == .volumeUp || self == .brightnessUp }
}

public struct MonitorKeyEvent {
    public let key: MonitorMediaKey
    public let isDown: Bool
    public let isRepeat: Bool

    public init?(subtype: Int16, data1: Int) {
        guard subtype == 8, let key = MonitorMediaKey(rawValue: (data1 >> 16) & 0xffff) else { return nil }
        let state = (data1 >> 8) & 0xff
        guard state == 0x0a || state == 0x0b else { return nil }
        self.key = key
        isDown = state == 0x0a
        isRepeat = data1 & 1 != 0
    }

    public init?(brightnessKeyCode: Int64, isDown: Bool, isRepeat: Bool) {
        guard brightnessKeyCode == 144 || brightnessKeyCode == 145 else { return nil }
        key = brightnessKeyCode == 144 ? .brightnessUp : .brightnessDown
        self.isDown = isDown
        self.isRepeat = isRepeat
    }
}

/// Latch a key's route until release, including pass-through routes.
public struct MonitorKeyTracker {
    private var held: [MonitorMediaKey: [UInt32]] = [:]
    public init() {}

    public mutating func handle(_ event: MonitorKeyEvent, candidates: [UInt32]) -> (consume: Bool, targets: [UInt32]) {
        if !event.isDown {
            return (!(held.removeValue(forKey: event.key) ?? []).isEmpty, [])
        }
        if !event.isRepeat { held[event.key] = candidates }
        let targets = held[event.key] ?? []
        return (!targets.isEmpty, event.key == .mute && event.isRepeat ? [] : targets)
    }
}

public struct MonitorLevel: Equatable {
    public private(set) var current: UInt16
    public let maximum: UInt16
    private var beforeMute: UInt16?

    public init?(current: UInt16, maximum: UInt16) {
        guard maximum > 0, current <= maximum else { return nil }
        self.current = current
        self.maximum = maximum
    }

    public func refreshed(with reading: MonitorLevel) -> MonitorLevel {
        // Keep the unmute level through a read-only wake/activation refresh.
        if current == 0, reading.current == 0, maximum == reading.maximum { return self }
        return reading
    }

    public mutating func apply(_ key: MonitorMediaKey, fine: Bool) {
        if key == .mute {
            if current == 0 {
                current = beforeMute ?? max(1, UInt16((Double(maximum) / 16).rounded()))
                beforeMute = nil
            } else {
                beforeMute = current
                current = 0
            }
            return
        }
        beforeMute = nil
        let step = max(1, Int((Double(maximum) / (fine ? 64 : 16)).rounded()))
        current = UInt16(min(Int(maximum), max(0, Int(current) + (key.isUp ? step : -step))))
    }
}

public struct MonitorDescriptor: Equatable {
    public let id: UInt32
    public let name: String
    public let isBuiltIn: Bool
    public let mirrorSource: UInt32

    public init(id: UInt32, name: String, isBuiltIn: Bool = false, mirrorSource: UInt32 = 0) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.mirrorSource = mirrorSource
    }
}

public enum MonitorRouting {
    public static func brightness(displays: [MonitorDescriptor], pointerDisplay: UInt32?, supported: Set<UInt32>) -> [UInt32] {
        guard let pointerDisplay else { return [] }
        return displays.filter {
            !$0.isBuiltIn && supported.contains($0.id) && ($0.id == pointerDisplay || $0.mirrorSource == pointerDisplay)
        }.map(\.id)
    }

    public static func volume(displays: [MonitorDescriptor], audioName: String?, isDisplayAudio: Bool,
                              hasNativeVolume: Bool, supported: Set<UInt32>) -> UInt32? {
        guard isDisplayAudio, !hasNativeVolume else { return nil }
        let external = displays.filter { !$0.isBuiltIn }
        let name = normalized(audioName ?? "")
        let matches = external.filter { !name.isEmpty && normalized($0.name) == name }
        if matches.count == 1 { return supported.contains(matches[0].id) ? matches[0].id : nil }
        // A generic HDMI audio name can be routed safely only with one external screen.
        guard matches.isEmpty, external.count == 1, supported.contains(external[0].id) else { return nil }
        return external[0].id
    }

    private static func normalized(_ string: String) -> String {
        string.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

/// Resolve scored display/service identities only when the best match is unambiguous.
public enum MonitorServiceMatching {
    public struct Candidate {
        public let display: UInt32
        public let service: Int
        public let score: Int
        public init(display: UInt32, service: Int, score: Int) {
            self.display = display; self.service = service; self.score = score
        }
    }

    public static func resolve(_ candidates: [Candidate]) -> [UInt32: Int] {
        var remaining = candidates.filter { $0.score >= 2 }
        var result: [UInt32: Int] = [:]
        while let best = remaining.max(by: { $0.score < $1.score }) {
            let tied = remaining.filter { $0.score == best.score && ($0.display == best.display || $0.service == best.service) }
            if tied.count == 1 {
                result[best.display] = best.service
                remaining.removeAll { $0.display == best.display || $0.service == best.service }
            } else {
                let displays = Set(tied.map(\.display))
                let services = Set(tied.map(\.service))
                remaining.removeAll { displays.contains($0.display) || services.contains($0.service) }
            }
        }
        return result
    }
}
