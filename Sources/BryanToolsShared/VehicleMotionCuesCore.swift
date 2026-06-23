import Darwin
import Foundation

public struct VehicleMotionCuesPreferences: Equatable {
    public static let defaultTrayEnabled = true

    public var isTrayEnabled: Bool

    public init(isTrayEnabled: Bool) {
        self.isTrayEnabled = isTrayEnabled
    }

    public static func load(defaults: UserDefaults = .standard) -> VehicleMotionCuesPreferences {
        let isTrayEnabled: Bool
        if defaults.object(forKey: "vehicleMotionCues.isTrayEnabled") == nil {
            isTrayEnabled = defaultTrayEnabled
        } else {
            isTrayEnabled = defaults.bool(forKey: "vehicleMotionCues.isTrayEnabled")
        }
        return VehicleMotionCuesPreferences(isTrayEnabled: isTrayEnabled)
    }

    public func save(defaults: UserDefaults = .standard) {
        defaults.set(isTrayEnabled, forKey: "vehicleMotionCues.isTrayEnabled")
    }
}

public enum VehicleMotionCuesError: Error, LocalizedError, Equatable {
    case frameworkUnavailable(String)
    case symbolUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .frameworkUnavailable(path):
            return "Vehicle Motion Cues framework is unavailable at \(path)"
        case let .symbolUnavailable(symbol):
            return "Vehicle Motion Cues system symbol is unavailable: \(symbol)"
        }
    }
}

public struct VehicleMotionCuesSnapshot: Equatable {
    public let isSupported: Bool
    public let isEnabled: Bool
    public let isActive: Bool

    public init(isSupported: Bool, isEnabled: Bool, isActive: Bool) {
        self.isSupported = isSupported
        self.isEnabled = isEnabled
        self.isActive = isActive
    }

    public var isOn: Bool {
        isSupported && isEnabled && isActive
    }
}

public enum VehicleMotionCuesDisplay {
    public static func systemImageName(for snapshot: VehicleMotionCuesSnapshot) -> String {
        guard snapshot.isSupported else {
            return "car.side"
        }
        return snapshot.isOn ? "car.side.fill" : "car.side"
    }

    public static func tooltip(for snapshot: VehicleMotionCuesSnapshot) -> String {
        guard snapshot.isSupported else {
            return "Vehicle Motion Cues unavailable on this Mac"
        }
        if snapshot.isOn {
            return "Vehicle Motion Cues: On"
        }
        if snapshot.isEnabled {
            return "Vehicle Motion Cues: Enabled, not active"
        }
        return "Vehicle Motion Cues: Off"
    }

    public static func accessibilityLabel(for snapshot: VehicleMotionCuesSnapshot) -> String {
        guard snapshot.isSupported else {
            return "Vehicle Motion Cues unavailable"
        }
        return snapshot.isEnabled ? "Turn Vehicle Motion Cues off" : "Turn Vehicle Motion Cues on"
    }
}

public final class SystemVehicleMotionCuesController {
    public static let motionCuesServicesPath =
        "/System/Library/PrivateFrameworks/AXMotionCuesServices.framework/Versions/A/AXMotionCuesServices"
    public static let accessibilityUtilitiesPath =
        "/System/Library/PrivateFrameworks/AccessibilityUtilities.framework/Versions/A/AccessibilityUtilities"
    public static let preferenceDidChangeNotificationName = "com.apple.accessibility.motion.cues.changed"

    private typealias BoolGetter = @convention(c) () -> Bool
    private typealias BoolSetter = @convention(c) (Bool) -> Void

    private let motionCuesServicesPath: String
    private let accessibilityUtilitiesPath: String
    private var motionCuesServicesHandle: UnsafeMutableRawPointer?
    private var accessibilityUtilitiesHandle: UnsafeMutableRawPointer?

    public init(
        motionCuesServicesPath: String = SystemVehicleMotionCuesController.motionCuesServicesPath,
        accessibilityUtilitiesPath: String = SystemVehicleMotionCuesController.accessibilityUtilitiesPath
    ) {
        self.motionCuesServicesPath = motionCuesServicesPath
        self.accessibilityUtilitiesPath = accessibilityUtilitiesPath
    }

    deinit {
        if let motionCuesServicesHandle {
            dlclose(motionCuesServicesHandle)
        }
        if let accessibilityUtilitiesHandle {
            dlclose(accessibilityUtilitiesHandle)
        }
    }

    public func snapshot(reconcileActiveState: Bool = false) throws -> VehicleMotionCuesSnapshot {
        let supported = try isSupported()
        let enabled = try isEnabled()
        if reconcileActiveState, supported {
            let active = try isActive()
            if enabled || active != enabled {
                try setActive(enabled)
            }
        }
        return VehicleMotionCuesSnapshot(
            isSupported: supported,
            isEnabled: enabled,
            isActive: try isActive()
        )
    }

    public func isSupported() throws -> Bool {
        guard let getter = optionalGetter(named: "UAMotionCuesIsSupported") else {
            return true
        }
        return getter()
    }

    public func isEnabled() throws -> Bool {
        try requiredGetter(named: "_AXSMotionCuesEnabled")()
    }

    public func isActive() throws -> Bool {
        try requiredGetter(named: "_AXSMotionCuesActive", loadFrom: .motionCuesServices)()
    }

    @discardableResult
    public func toggleEnabled() throws -> VehicleMotionCuesSnapshot {
        let current = try snapshot()
        guard current.isSupported else {
            return current
        }
        try setEnabledAndActive(!current.isEnabled)
        return try snapshot()
    }

    public func setEnabled(_ isEnabled: Bool) throws {
        try requiredSetter(named: "_AXSSetMotionCuesEnabled")(isEnabled)
    }

    public func setActive(_ isActive: Bool) throws {
        try requiredSetter(named: "_AXSSetMotionCuesActive", loadFrom: .motionCuesServices)(isActive)
    }

    public func setEnabledAndActive(_ isEnabled: Bool) throws {
        try setEnabled(isEnabled)
        try setActive(isEnabled)
    }

    private func requiredGetter(named symbolName: String, loadFrom library: Library = .accessibilityUtilities) throws -> BoolGetter {
        guard let getter = optionalGetter(named: symbolName, loadFrom: library) else {
            throw VehicleMotionCuesError.symbolUnavailable(symbolName)
        }
        return getter
    }

    private func optionalGetter(named symbolName: String, loadFrom library: Library = .accessibilityUtilities) -> BoolGetter? {
        guard let symbol = try? loadSymbol(named: symbolName, loadFrom: library) else {
            return nil
        }
        return unsafeBitCast(symbol, to: BoolGetter.self)
    }

    private func requiredSetter(named symbolName: String, loadFrom library: Library = .accessibilityUtilities) throws -> BoolSetter {
        let symbol = try loadSymbol(named: symbolName, loadFrom: library)
        return unsafeBitCast(symbol, to: BoolSetter.self)
    }

    private func loadSymbol(named symbolName: String, loadFrom library: Library) throws -> UnsafeMutableRawPointer {
        let handle = try loadLibrary(library)
        guard let symbol = dlsym(handle, symbolName) else {
            throw VehicleMotionCuesError.symbolUnavailable(symbolName)
        }
        return symbol
    }

    private func loadLibrary(_ library: Library) throws -> UnsafeMutableRawPointer {
        switch library {
        case .accessibilityUtilities:
            return try loadAccessibilityUtilities()
        case .motionCuesServices:
            return try loadMotionCuesServices()
        }
    }

    private func loadAccessibilityUtilities() throws -> UnsafeMutableRawPointer {
        if let accessibilityUtilitiesHandle {
            return accessibilityUtilitiesHandle
        }
        guard let handle = dlopen(accessibilityUtilitiesPath, RTLD_NOW) else {
            throw VehicleMotionCuesError.frameworkUnavailable(accessibilityUtilitiesPath)
        }
        accessibilityUtilitiesHandle = handle
        return handle
    }

    private func loadMotionCuesServices() throws -> UnsafeMutableRawPointer {
        if let motionCuesServicesHandle {
            return motionCuesServicesHandle
        }
        guard let handle = dlopen(motionCuesServicesPath, RTLD_NOW) else {
            throw VehicleMotionCuesError.frameworkUnavailable(motionCuesServicesPath)
        }
        motionCuesServicesHandle = handle
        return handle
    }

    private enum Library {
        case accessibilityUtilities
        case motionCuesServices
    }
}
