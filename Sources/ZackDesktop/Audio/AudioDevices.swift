import CoreAudio
import Foundation
import os

/// The system default input device via Core Audio.
public enum AudioDevices {
    /// ID of the system default input device, which `AVAudioEngine` records from; nil if there is none.
    public static func defaultInputID() -> AudioObjectID? {
        var address = defaultInputAddress
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
                == noErr, device != kAudioObjectUnknown
        else { return nil }
        return device
    }

    /// Whether the device is still present and usable (`kAudioDevicePropertyDeviceIsAlive`).
    public static func isAlive(_ device: AudioObjectID) -> Bool {
        var address = aliveAddress
        var alive: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &alive) == noErr else { return false }
        return alive != 0
    }

    /// Name of the system default input device; nil if there is none.
    public static func defaultInputName() -> String? {
        guard let device = defaultInputID() else { return nil }
        return stringProperty(kAudioObjectPropertyName, of: device)
    }

    /// All visible devices with at least one input stream and a UID, in Core Audio order.
    public static func inputDevices() -> [InputDevice] {
        var address = devicesAddress
        var size: UInt32 = 0
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](
            repeating: AudioObjectID(kAudioObjectUnknown), count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            let transport = transportType(id)
            guard
                let uid = stringProperty(kAudioDevicePropertyDeviceUID, of: id),
                isListable(
                    transportType: transport,
                    isPrivateAggregate: transport == kAudioDeviceTransportTypeAggregate ? isPrivateAggregate(id) : nil,
                    isHidden: isHidden(id), hasInputStreams: hasInputStream(id), uid: uid)
            else { return nil }
            return InputDevice(id: id, uid: uid, name: stringProperty(kAudioObjectPropertyName, of: id) ?? "")
        }
    }

    /// Whether a device belongs in the microphone list. A private aggregate (such as the helper device
    /// `AVAudioEngine` creates inside the process) is not a choice; an unreadable composition (nil) keeps the device.
    static func isListable(
        transportType: UInt32, isPrivateAggregate: Bool?, isHidden: Bool, hasInputStreams: Bool, uid: String
    ) -> Bool {
        if transportType == kAudioDeviceTransportTypeAggregate && isPrivateAggregate == true { return false }
        return hasInputStreams && !isHidden && !uid.isEmpty
    }

    /// Calls `handler` on the main queue whenever the default input changes, as long as the result is kept.
    public static func observeDefaultInput(_ handler: @escaping @Sendable () -> Void) -> AudioPropertyObservation {
        AudioPropertyObservation(defaultInputAddress, handler)
    }

    /// Calls `handler` on the main queue whenever devices are added or removed, as long as the result is kept.
    public static func observeDeviceList(_ handler: @escaping @Sendable () -> Void) -> AudioPropertyObservation {
        AudioPropertyObservation(devicesAddress, handler)
    }

    /// Calls `handler` on `queue` whenever `device` comes alive or dies, as long as the result is kept.
    public static func observeAlive(
        _ device: AudioObjectID, queue: DispatchQueue, _ handler: @escaping @Sendable () -> Void
    ) -> AudioPropertyObservation {
        AudioPropertyObservation(aliveAddress, of: device, queue: queue, handler)
    }

    private static func hasInputStream(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func transportType(_ device: AudioObjectID) -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var type: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &type) == noErr else { return 0 }
        return type
    }

    /// Whether the aggregate's composition marks it private; nil if the composition cannot be read.
    private static func isPrivateAggregate(_ device: AudioObjectID) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioAggregateDevicePropertyComposition, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFDictionary>?
        var size = UInt32(MemoryLayout<Unmanaged<CFDictionary>?>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr, let value else {
            return nil
        }
        let composition = value.takeRetainedValue() as NSDictionary
        return (composition[kAudioAggregateDeviceIsPrivateKey] as? NSNumber)?.boolValue ?? false
    }

    private static func isHidden(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyIsHidden, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var hidden: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &hidden) == noErr && hidden != 0
    }

    /// Reads a CFString property of an audio object; nil if it is not delivered.
    static func stringProperty(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, let value else {
            return nil
        }
        return value.takeRetainedValue() as String
    }

    static var devicesAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    static var aliveAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsAlive, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }

    static var defaultInputAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
    }
}

/// Subscription to a property of an audio object, by default the system object; ends when released.
public final class AudioPropertyObservation: @unchecked Sendable {
    // Core Audio keeps the block; it is only ever called on `queue`.
    private let block: AudioObjectPropertyListenerBlock
    private let object: AudioObjectID
    private let address: AudioObjectPropertyAddress
    private let queue: DispatchQueue
    private static let logger = Logger(subsystem: "com.netclusive.zack", category: "audio")

    init(
        _ address: AudioObjectPropertyAddress, of object: AudioObjectID = AudioObjectID(kAudioObjectSystemObject),
        queue: DispatchQueue = .main, _ handler: @escaping @Sendable () -> Void
    ) {
        self.address = address
        self.object = object
        self.queue = queue
        block = { _, _ in handler() }
        var address = address
        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
        if status != noErr { Self.logger.error("audio observer not added, status \(status)") }
    }

    deinit {
        var address = address
        let status = AudioObjectRemovePropertyListenerBlock(object, &address, queue, block)
        if status != noErr { Self.logger.error("audio observer not removed, status \(status)") }
    }
}
