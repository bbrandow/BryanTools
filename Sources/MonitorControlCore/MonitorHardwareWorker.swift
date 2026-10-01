import Foundation

public struct MonitorControlAddress: Hashable {
    public let display: UInt32
    public let feature: MonitorFeature
    public init(display: UInt32, feature: MonitorFeature) { self.display = display; self.feature = feature }
}

/// Coalesce repeat keys to one pending value per control instead of an unbounded I/O backlog.
public final class MonitorWriteBuffer {
    private let lock = NSLock()
    private var generation: UInt64 = 0
    private var pending: [MonitorControlAddress: UInt16] = [:]
    private var scheduled = false
    private var failed: Set<MonitorControlAddress> = []

    public init() {}

    public func invalidate() -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        pending.removeAll()
        failed.removeAll()
        scheduled = false
        return generation
    }

    public func isCurrent(_ token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return token == generation
    }

    public func enqueue(_ address: MonitorControlAddress, value: UInt16, generation token: UInt64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard token == generation, !failed.contains(address) else { return false }
        pending[address] = value
        guard !scheduled else { return false }
        scheduled = true
        return true
    }

    public func take(generation token: UInt64) -> [MonitorControlAddress: UInt16]? {
        lock.lock(); defer { lock.unlock() }
        guard token == generation else { return nil }
        guard !pending.isEmpty else { scheduled = false; return nil }
        let values = pending
        pending.removeAll()
        return values
    }

    public func fail(_ address: MonitorControlAddress, generation token: UInt64) {
        lock.lock(); defer { lock.unlock() }
        guard token == generation else { return }
        failed.insert(address)
        pending.removeValue(forKey: address)
    }
}

public final class MonitorHardwareWorker {
    public typealias Levels = [MonitorControlAddress: MonitorLevel]
    private let queue = DispatchQueue(label: "com.local.BryanTools.monitorHardware", qos: .utility)
    private let buffer = MonitorWriteBuffer()
    private let discover: ([MonitorDescriptor]) -> [UInt32: any MonitorTransport]
    // Only accessed on queue.
    private var transports: [UInt32: any MonitorTransport] = [:]

    public init(discover: @escaping ([MonitorDescriptor]) -> [UInt32: any MonitorTransport] = {
        MonitorDDCConnection.discover(displays: $0).mapValues { $0 as any MonitorTransport }
    }) {
        self.discover = discover
    }

    @discardableResult
    public func refresh(_ displays: [MonitorDescriptor], completion: @escaping (UInt64, Levels) -> Void) -> UInt64 {
        let token = buffer.invalidate()
        queue.async { [self] in
            guard buffer.isCurrent(token) else { return }
            transports = discover(displays)
            var levels: Levels = [:]
            for (id, transport) in transports {
                for feature in [MonitorFeature.brightness, .volume] {
                    guard buffer.isCurrent(token) else { return }
                    if let level = transport.read(feature) {
                        levels[.init(display: id, feature: feature)] = level
                    }
                }
            }
            DispatchQueue.main.async { [self] in
                if buffer.isCurrent(token) { completion(token, levels) }
            }
        }
        return token
    }

    public func stop() {
        _ = buffer.invalidate()
        queue.async { [self] in transports.removeAll() }
    }

    public func set(_ address: MonitorControlAddress, value: UInt16, generation: UInt64,
                    failed: @escaping (MonitorControlAddress) -> Void) {
        guard buffer.enqueue(address, value: value, generation: generation) else { return }
        queue.async { [self] in drain(generation: generation, failed: failed) }
    }

    private func drain(generation: UInt64, failed: @escaping (MonitorControlAddress) -> Void) {
        guard let values = buffer.take(generation: generation) else { return }
        for (address, value) in values {
            guard buffer.isCurrent(generation) else { return }
            if transports[address.display]?.write(address.feature, value: value) != true {
                buffer.fail(address, generation: generation)
                DispatchQueue.main.async { [self] in
                    if buffer.isCurrent(generation) { failed(address) }
                }
            }
        }
        queue.async { [self] in drain(generation: generation, failed: failed) }
    }
}
