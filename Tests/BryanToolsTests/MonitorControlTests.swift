import BryanToolsShared
import Foundation
import MonitorControlCore
import MonitorHardware

enum MonitorControlTests {
    static let tests: [(String, () throws -> Void)] = [
        ("Monitor Controls identity and keyboard decoding", keyboard),
        ("Monitor Controls balanced key repeat and release", keyTracking),
        ("Monitor Controls levels, limits, fine steps and mute", levels),
        ("Monitor Controls brightness and audio routing", routing),
        ("Monitor Controls conservative display matching", matching),
        ("Monitor Controls DDC reply validation", replies),
        ("Monitor Controls bounded writes and stale generations", writeBuffer),
        ("Monitor Controls background discovery, writes and failure", worker),
        ("Monitor Controls canceled discovery does not publish", canceledDiscovery)
    ]

    private struct Failure: Error { let message: String }
    private static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw Failure(message: message) }
    }
    private static func event(_ key: MonitorMediaKey, down: Bool = true, repeatKey: Bool = false) -> MonitorKeyEvent {
        MonitorKeyEvent(subtype: 8, data1: (key.rawValue << 16) | (down ? 0x0a00 : 0x0b00) | (repeatKey ? 1 : 0))!
    }

    private static func keyboard() throws {
        try check(ToolIdentifier.monitorControl.displayName == "Monitor Controls", "Expected independent tool")
        for key in [MonitorMediaKey.brightnessDown, .brightnessUp, .volumeDown, .volumeUp, .mute] {
            try check(event(key).key == key && event(key).isDown, "Expected media key down")
            try check(!event(key, down: false).isDown, "Expected media key up")
            try check(event(key, repeatKey: true).isRepeat, "Expected repeat flag")
        }
        try check(MonitorKeyEvent(subtype: 7, data1: 0x0a00) == nil, "Ignore unrelated system events")
        try check(MonitorKeyEvent(subtype: 8, data1: (16 << 16) | 0x0a00) == nil, "Do not capture play/pause")
        try check(MonitorKeyEvent(subtype: 8, data1: 0) == nil, "Ignore invalid key state")
        try check(MonitorKeyEvent(brightnessKeyCode: 144, isDown: true, isRepeat: false)?.key == .brightnessUp, "Dedicated brightness key")
        try check(MonitorKeyEvent(brightnessKeyCode: 122, isDown: true, isRepeat: false) == nil, "Do not hijack normal F1")
    }

    private static func keyTracking() throws {
        var tracker = MonitorKeyTracker()
        try check(tracker.handle(event(.volumeUp), candidates: [2]).targets == [2], "Route initial press")
        try check(tracker.handle(event(.volumeUp, repeatKey: true), candidates: [3]).targets == [2], "Hold route for repeats")
        let release = tracker.handle(event(.volumeUp, down: false), candidates: [])
        try check(release.consume && release.targets.isEmpty, "Consume keyup without another write")
        try check(!tracker.handle(event(.volumeUp, down: false), candidates: [2]).consume, "Do not swallow unhandled keyup")
        try check(!tracker.handle(event(.brightnessUp), candidates: []).consume, "Pass through unsupported key")
        try check(!tracker.handle(event(.brightnessUp, repeatKey: true), candidates: [2]).consume, "Do not steal a held native key")
        try check(tracker.handle(event(.mute), candidates: [2]).targets == [2], "Mute once")
        let muteRepeat = tracker.handle(event(.mute, repeatKey: true), candidates: [2])
        try check(muteRepeat.consume && muteRepeat.targets.isEmpty, "Held mute must not repeatedly toggle")
    }

    private static func levels() throws {
        try check(MonitorLevel(current: 1, maximum: 0) == nil, "Invalid maximum")
        try check(MonitorLevel(current: 101, maximum: 100) == nil, "Invalid current")
        var normal = MonitorLevel(current: 50, maximum: 100)!
        normal.apply(.brightnessUp, fine: false)
        try check(normal.current == 56, "Normal step")
        normal.apply(.brightnessDown, fine: true)
        try check(normal.current == 54, "Fine step")
        for _ in 0..<100 { normal.apply(.brightnessUp, fine: false) }
        try check(normal.current == 100, "Upper bound")
        for _ in 0..<100 { normal.apply(.brightnessDown, fine: false) }
        try check(normal.current == 0, "Lower bound")
        var volume = MonitorLevel(current: 37, maximum: 100)!
        volume.apply(.mute, fine: false)
        try check(volume.current == 0, "Mute using speaker volume only, never screen blanking")
        volume = volume.refreshed(with: MonitorLevel(current: 0, maximum: 100)!)
        volume.apply(.mute, fine: false)
        try check(volume.current == 37, "Restore previous volume even after hardware refresh")
        let changed = volume.refreshed(with: MonitorLevel(current: 80, maximum: 100)!)
        try check(changed.current == 80, "Respect externally changed values on refresh")
        volume.apply(.mute, fine: false)
        volume.apply(.volumeUp, fine: false)
        try check(volume.current == 6, "Volume up from mute increments from silence")
        var fullRange = MonitorLevel(current: 65530, maximum: 65535)!
        fullRange.apply(.volumeUp, fine: false)
        try check(fullRange.current == 65535, "No overflow with 16-bit range")
    }

    private static func routing() throws {
        let displays: [MonitorDescriptor] = [.init(id: 1, name: "Internal", isBuiltIn: true), .init(id: 2, name: "DELL U2720Q")]
        try check(MonitorRouting.brightness(displays: displays, pointerDisplay: 2, supported: [2]) == [2], "Brightness under pointer")
        try check(MonitorRouting.brightness(displays: displays, pointerDisplay: 1, supported: [2]).isEmpty, "Leave built-in brightness native")
        try check(MonitorRouting.brightness(displays: displays, pointerDisplay: 2, supported: []).isEmpty, "Unsupported brightness passes through")
        let mirrored = displays + [.init(id: 3, name: "Mirror", mirrorSource: 1)]
        try check(MonitorRouting.brightness(displays: mirrored, pointerDisplay: 1, supported: [2, 3]) == [3], "Route to physical mirrored screen")
        func volume(_ list: [MonitorDescriptor], _ name: String, displayAudio: Bool = true, native: Bool = false) -> UInt32? {
            MonitorRouting.volume(displays: list, audioName: name, isDisplayAudio: displayAudio, hasNativeVolume: native, supported: [2, 3])
        }
        try check(volume(displays, "HDMI") == 2, "Single HDMI display fallback")
        try check(volume(displays, "DELL U2720Q", native: true) == nil, "Respect native USB audio volume")
        try check(volume(displays, "Bluetooth", displayAudio: false) == nil, "Never route Bluetooth sound to monitor")
        let multiple = displays + [.init(id: 3, name: "LG Display")]
        try check(volume(multiple, "dell-u2720q") == 2, "Unambiguous audio name")
        try check(volume(multiple, "HDMI") == nil, "Do not guess between monitors")
        try check(volume(displays + [.init(id: 3, name: "DELL U2720Q")], "DELL U2720Q") == nil, "Identical names need a safe match")
        try check(MonitorRouting.volume(displays: multiple, audioName: "LG Display", isDisplayAudio: true,
                                        hasNativeVolume: false, supported: [2]) == nil, "Do not fall back to a different supported monitor")
    }

    private static func matching() throws {
        typealias C = MonitorServiceMatching.Candidate
        try check(MonitorServiceMatching.resolve([C(display: 1, service: 0, score: 1)]).isEmpty, "Name alone insufficient")
        let exact = [C(display: 1, service: 0, score: 12), C(display: 1, service: 1, score: 2),
                     C(display: 2, service: 0, score: 2), C(display: 2, service: 1, score: 12)]
        try check(MonitorServiceMatching.resolve(exact) == [1: 0, 2: 1], "Prefer exact location matches")
        try check(MonitorServiceMatching.resolve([C(display: 1, service: 0, score: 2), C(display: 2, service: 0, score: 2)]).isEmpty, "Ambiguous display identity")
        try check(MonitorServiceMatching.resolve([C(display: 1, service: 0, score: 2), C(display: 1, service: 1, score: 2)]).isEmpty, "Ambiguous service identity")
    }

    private static func replies() throws {
        func packet(_ bytes: [UInt8]) -> [UInt8] { bytes + [bytes.reduce(UInt8(0x50), ^)] }
        let valid = packet([0x6e, 0x88, 0x02, 0, 0x10, 0, 0x01, 0xff, 0x01, 0x80])
        var current: UInt16 = 0, maximum: UInt16 = 0
        func parse(_ bytes: [UInt8], code: UInt8 = 0x10) -> Bool {
            bytes.withUnsafeBufferPointer { BTMonitorParseReply($0.baseAddress!, $0.count, code, &current, &maximum) }
        }
        try check(parse(valid) && current == 384 && maximum == 511, "Full 16-bit reply without truncation")
        try check(!parse(valid, code: 0x62), "Reply must match requested VCP code")
        try check(!parse(Array(valid.dropLast())), "Reject short reply")
        var corrupt = valid; corrupt[10] ^= 1
        try check(!parse(corrupt), "Reject checksum corruption")
        try check(!parse(packet([0x6e, 0x88, 0x02, 1, 0x10, 0, 0, 100, 0, 50])), "Unsupported VCP response")
        try check(!parse(packet([0x6e, 0x88, 0x02, 0, 0x10, 0, 0, 0, 0, 0])), "Zero maximum")
        try check(!parse(packet([0x6e, 0x88, 0x02, 0, 0x10, 0, 0, 10, 0, 50])), "Out-of-range reply")
        try check(!parse(packet([0, 0x88, 0x02, 0, 0x10, 0, 0, 100, 0, 50])), "Wrong source address")
    }

    private static func writeBuffer() throws {
        let buffer = MonitorWriteBuffer()
        let address = MonitorControlAddress(display: 2, feature: .brightness)
        let generation = buffer.invalidate()
        try check(buffer.enqueue(address, value: 1, generation: generation), "Schedule first drain")
        for value in 2...1000 { try check(!buffer.enqueue(address, value: UInt16(value), generation: generation), "Only one queued drain") }
        try check(buffer.take(generation: generation) == [address: 1000], "Bounded coalescing uses newest value")
        try check(buffer.take(generation: generation) == nil, "Stop draining when empty")
        try check(buffer.enqueue(address, value: 2, generation: generation), "Schedule after idle")
        buffer.fail(address, generation: generation)
        try check(buffer.take(generation: generation) == nil, "Drop writes to failed control")
        try check(!buffer.enqueue(address, value: 3, generation: generation), "No repeat storm on failed monitor")
        let next = buffer.invalidate()
        try check(!buffer.enqueue(address, value: 4, generation: generation), "Discard stale hotplug work")
        try check(buffer.enqueue(address, value: 5, generation: next), "New connection may retry")
        try check(buffer.take(generation: generation) == nil, "Old drain cannot consume new writes")
        try check(buffer.take(generation: next) == [address: 5], "New generation survives old drain")
    }

    private final class Transport: MonitorTransport {
        private let lock = NSLock()
        private var operations: [(MonitorFeature, UInt16)] = []
        private var background = true
        var failWrites = false
        var readGate: DispatchSemaphore?
        let entered = DispatchSemaphore(value: 0)
        func read(_ feature: MonitorFeature) -> MonitorLevel? {
            lock.lock(); background = background && !Thread.isMainThread; lock.unlock()
            entered.signal()
            if let readGate { _ = readGate.wait(timeout: .now() + 3) }
            return feature == .brightness ? MonitorLevel(current: 50, maximum: 100) : nil
        }
        func write(_ feature: MonitorFeature, value: UInt16) -> Bool {
            lock.lock(); defer { lock.unlock() }
            background = background && !Thread.isMainThread
            operations.append((feature, value))
            return !failWrites
        }
        var writes: [(MonitorFeature, UInt16)] { lock.lock(); defer { lock.unlock() }; return operations }
        var allBackground: Bool { lock.lock(); defer { lock.unlock() }; return background }
    }

    private static func wait(_ predicate: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        try check(predicate(), "Timed out waiting for background test")
    }

    private static func worker() throws {
        let healthy = Transport()
        let healthyWorker = MonitorHardwareWorker(discover: { _ in [3: healthy] })
        defer { healthyWorker.stop() }
        var ready = false
        let healthyToken = healthyWorker.refresh([.init(id: 3, name: "Healthy")]) { _, _ in ready = true }
        try wait { ready }
        var unexpectedFailure = false
        let healthyAddress = MonitorControlAddress(display: 3, feature: .brightness)
        for value in UInt16(51)...100 {
            healthyWorker.set(healthyAddress, value: value, generation: healthyToken) { _ in unexpectedFailure = true }
        }
        try wait { healthy.writes.last?.1 == 100 }
        try check(!unexpectedFailure && healthy.allBackground, "Successful repeats converge to the latest level off the UI thread")
        let transport = Transport()
        transport.failWrites = true
        let worker = MonitorHardwareWorker(discover: { _ in [2: transport] })
        defer { worker.stop() }
        var snapshot: MonitorHardwareWorker.Levels?
        let token = worker.refresh([.init(id: 2, name: "Fixture")]) { _, levels in snapshot = levels }
        try wait { snapshot != nil }
        let address = MonitorControlAddress(display: 2, feature: .brightness)
        try check(snapshot?.count == 1 && snapshot?[address]?.current == 50, "Only probe-supported controls enabled")
        try check(transport.writes.isEmpty, "Discovery must never change hardware")
        var failure: MonitorControlAddress?
        worker.set(address, value: 56, generation: token) { failure = $0 }
        try wait { failure != nil }
        try check(failure == address && transport.writes.count == 1, "Publish hardware failure once")
        try check(transport.allBackground, "All reads and writes off UI thread")
        worker.set(address, value: 62, generation: token) { failure = $0 }
        worker.stop()
        try check(transport.writes.count == 1, "Failed control does not keep writing")
    }

    private static func canceledDiscovery() throws {
        let transport = Transport()
        let gate = DispatchSemaphore(value: 0)
        transport.readGate = gate
        let worker = MonitorHardwareWorker(discover: { _ in [2: transport] })
        var published = false
        _ = worker.refresh([.init(id: 2, name: "Fixture")]) { _, _ in published = true }
        let entered = transport.entered.wait(timeout: .now() + 3)
        worker.stop()
        gate.signal()
        try check(entered == .success, "Probe started")
        var finished = false
        _ = worker.refresh([]) { _, _ in finished = true }
        // The injected fixture still returns a connection; unblock both of its reads.
        gate.signal(); gate.signal()
        try wait { finished }
        worker.stop()
        try check(!published && transport.writes.isEmpty, "No stale result or hardware changes after stop")
    }
}
