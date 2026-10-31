import CoreAudio

/// A connected audio input device.
public struct InputDevice: Equatable, Sendable {
    public let id: AudioObjectID
    public let uid: String
    public let name: String

    public init(id: AudioObjectID, uid: String, name: String) {
        self.id = id
        self.uid = uid
        self.name = name
    }
}

/// The microphone the user picked, as stored: the UID is stable, the name is the fallback match.
public struct SavedMicrophone: Equatable, Sendable {
    public let uid: String
    public let name: String

    public init(uid: String, name: String) {
        self.uid = uid
        self.name = name
    }
}

public enum MicrophoneChoice {
    public enum Resolution: Equatable, Sendable {
        /// No choice stored: follow the macOS default.
        case system
        /// The stored microphone is connected.
        case chosen(InputDevice)
        /// A choice is stored but its device is missing or ambiguous: use the macOS default.
        case fallback

        /// The device to capture from; `nil` only when there is no default either.
        public func deviceID(default defaultID: AudioObjectID?) -> AudioObjectID? {
            if case .chosen(let device) = self { return device.id }
            return defaultID
        }
    }

    /// UID match first; otherwise a name that exactly one device carries (the same model at another port).
    public static func resolve(_ saved: SavedMicrophone?, in devices: [InputDevice]) -> Resolution {
        guard let saved else { return .system }
        if let device = devices.first(where: { $0.uid == saved.uid }) { return .chosen(device) }
        let named = devices.filter { $0.name == saved.name }
        if named.count == 1, let device = named.first { return .chosen(device) }
        return .fallback
    }
}
