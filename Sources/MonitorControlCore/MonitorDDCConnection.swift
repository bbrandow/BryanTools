// Display/service matching adapted from MonitorControl's Arm64DDC.swift.
// Copyright MonitorControl contributors. See ThirdParty/MonitorControl-LICENSE.txt.
import CoreGraphics
import Foundation
import IOKit
import MonitorHardware

public protocol MonitorTransport: AnyObject {
    func read(_ feature: MonitorFeature) -> MonitorLevel?
    func write(_ feature: MonitorFeature, value: UInt16) -> Bool
}

public final class MonitorDDCConnection: MonitorTransport {
    private let avService: CFTypeRef?
    private let framebuffer: io_service_t

    private init(avService: CFTypeRef? = nil, framebuffer: io_service_t = 0) {
        self.avService = avService
        self.framebuffer = framebuffer
    }

    deinit { if framebuffer != 0 { IOObjectRelease(framebuffer) } }

    public func read(_ feature: MonitorFeature) -> MonitorLevel? {
        var current: UInt16 = 0
        var maximum: UInt16 = 0
        let success: Bool
        if let avService {
            success = BTMonitorAVRead(avService, feature.rawValue, &current, &maximum)
        } else {
            success = BTMonitorIntelRead(framebuffer, feature.rawValue, &current, &maximum)
        }
        return success ? MonitorLevel(current: current, maximum: maximum) : nil
    }

    public func write(_ feature: MonitorFeature, value: UInt16) -> Bool {
        if let avService { return BTMonitorAVWrite(avService, feature.rawValue, value) }
        return BTMonitorIntelWrite(framebuffer, feature.rawValue, value)
    }

    /// Called only on the dedicated hardware queue, never from a keyboard callback.
    public static func discover(displays: [MonitorDescriptor]) -> [UInt32: MonitorDDCConnection] {
        let external = displays.filter { !$0.isBuiltIn }
        guard !external.isEmpty else { return [:] }
        #if arch(arm64)
        let services = appleSiliconServices()
        var candidates: [MonitorServiceMatching.Candidate] = []
        for display in external {
            let info = BTMonitorCopyInfo(display.id) as? [String: Any] ?? [:]
            if info["kCGDisplayIsVirtualDevice"] as? Bool == true || info["kCGDisplayIsAirPlay"] as? Bool == true { continue }
            for (index, service) in services.enumerated() {
                var score = 0
                if let location = info[kIODisplayLocationKey] as? String, !location.isEmpty, location == service.location { score += 10 }
                let vendor = String(format: "%04X", CGDisplayVendorNumber(display.id) & 0xffff)
                let model = CGDisplayModelNumber(display.id)
                let product = String(format: "%02X%02X", model & 0xff, (model >> 8) & 0xff)
                if service.edid.hasPrefix(vendor + product) { score += 2 }
                if !service.name.isEmpty, service.name.caseInsensitiveCompare(display.name) == .orderedSame { score += 1 }
                if service.serial != 0, service.serial == CGDisplaySerialNumber(display.id) { score += 2 }
                candidates.append(.init(display: display.id, service: index, score: score))
            }
        }
        return MonitorServiceMatching.resolve(candidates).mapValues { MonitorDDCConnection(avService: services[$0].service) }
        #else
        var result: [UInt32: MonitorDDCConnection] = [:]
        for display in external {
            let framebuffer = BTMonitorCopyFramebuffer(display.id)
            if framebuffer != 0 { result[display.id] = MonitorDDCConnection(framebuffer: framebuffer) }
        }
        return result
        #endif
    }

    private struct AVDisplay {
        let service: CFTypeRef
        let location: String
        let edid: String
        let name: String
        let serial: UInt32
    }

    private static func appleSiliconServices() -> [AVDisplay] {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return [] }
        defer { IOObjectRelease(root) }
        var iterator: io_iterator_t = 0
        guard IORegistryEntryCreateIterator(root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result: [AVDisplay] = []
        var location = "", edid = "", productName = ""
        var serial: UInt32 = 0
        while case let entry = IOIteratorNext(iterator), entry != 0 {
            defer { IOObjectRelease(entry) }
            var nameBuffer = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(entry, &nameBuffer) == KERN_SUCCESS else { continue }
            let name = String(cString: nameBuffer)
            if name == "AppleCLCD2" || name == "IOMobileFramebufferShim" {
                var path = [CChar](repeating: 0, count: 512)
                location = IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS ? String(cString: path) : ""
                edid = (property(entry, "EDID UUID") as? String ?? "").uppercased()
                let attributes = property(entry, "DisplayAttributes") as? [String: Any]
                let product = attributes?["ProductAttributes"] as? [String: Any]
                productName = product?["ProductName"] as? String ?? ""
                serial = (product?["SerialNumber"] as? NSNumber)?.uint32Value ?? 0
            } else if name == "DCPAVServiceProxy", property(entry, "Location") as? String == "External",
                      let service = BTMonitorCreateAVService(entry) {
                result.append(AVDisplay(service: service, location: location, edid: edid, name: productName, serial: serial))
            }
        }
        return result
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
