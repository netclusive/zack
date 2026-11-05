import CoreAudio

/// The processes with an active output stream, from Core Audio's process objects (macOS 14.2 and later).
public struct CoreAudioOutputs: AudioOutputs {
    struct ReadError: Error {
        let status: OSStatus
    }

    public init() {}

    public func playingBundleIDs() -> Set<String> {
        (try? read()) ?? []
    }

    /// Throws if the process list cannot be read; a process whose details cannot be read, or that has no bundle ID,
    /// is left out.
    func read() throws -> Set<String> {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size)
        guard status == noErr else { throw ReadError(status: status) }
        var processes = [AudioObjectID](
            repeating: AudioObjectID(kAudioObjectUnknown), count: Int(size) / MemoryLayout<AudioObjectID>.size)
        status = AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes)
        guard status == noErr else { throw ReadError(status: status) }
        // The list may have shrunk between the two calls.
        let read = processes.prefix(Int(size) / MemoryLayout<AudioObjectID>.size)
        let bundleIDs = read.filter(isRunningOutput).compactMap { process in
            AudioDevices.stringProperty(kAudioProcessPropertyBundleID, of: process)
        }
        return Set(bundleIDs.filter { !$0.isEmpty })
    }

    private func isRunningOutput(_ process: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput, mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr && running != 0
    }
}
