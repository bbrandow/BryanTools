import AudioToolbox
import CoreAudio
import Foundation

struct MonitorAudioOutput {
    let name: String
    let isDisplayAudio: Bool
    let hasNativeVolume: Bool

    static func read() -> Self? {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != kAudioObjectUnknown else { return nil }
        address.mSelector = kAudioObjectPropertyName
        var rawName: Unmanaged<CFString>?
        size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let nameResult = withUnsafeMutablePointer(to: &rawName) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        // CoreAudio transfers ownership of CF-valued properties to the caller.
        let name = rawName?.takeRetainedValue() as String? ?? ""
        guard nameResult == noErr else { return nil }
        var transport: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyTransportType
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &transport) == noErr else { return nil }
        let isDisplay = transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort
        // USB monitor audio and normal speakers expose native volume; leave these to macOS.
        let volumeProperties: [AudioObjectPropertySelector] = [kAudioDevicePropertyVolumeScalar, kAudioHardwareServiceDeviceProperty_VirtualMainVolume]
        let native = volumeProperties.contains { selector in
            (0...2).contains { element in
                var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                         mElement: AudioObjectPropertyElement(element))
                var writable: DarwinBoolean = false
                return AudioObjectHasProperty(device, &property)
                    && AudioObjectIsPropertySettable(device, &property, &writable) == noErr && writable.boolValue
            }
        }
        return Self(name: name, isDisplayAudio: isDisplay, hasNativeVolume: native)
    }
}

/// Event-driven; there is no idle hardware polling timer.
@MainActor
final class MonitorAudioOutputObserver {
    private var listener: AudioObjectPropertyListenerBlock?
    private let queue = DispatchQueue(label: "com.local.BryanTools.monitorAudio", qos: .utility)
    private var generation = 0
    private var onChange: ((MonitorAudioOutput?) -> Void)?

    func start(onChange: @escaping (MonitorAudioOutput?) -> Void) {
        stop()
        self.onChange = onChange
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        var address = Self.address
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block) == noErr {
            listener = block
        }
        refresh()
    }

    func refresh() {
        generation += 1
        let token = generation
        onChange?(nil) // Never route keys using a stale output while resolving the new device.
        queue.async { [weak self] in
            let output = MonitorAudioOutput.read()
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                self.onChange?(output)
            }
        }
    }

    func stop() {
        generation += 1
        if let listener {
            var address = Self.address
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
        }
        listener = nil
        onChange = nil
    }

    private static var address: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
}
