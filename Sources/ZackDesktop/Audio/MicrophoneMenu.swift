import CoreAudio
import Foundation

/// What the menu shows about the microphone: the status line, the options and the checked one.
public struct MicrophoneMenu: Equatable, Sendable {
    public struct Option: Equatable, Sendable, Identifiable {
        public let id: String
        public let title: String
        /// False for the saved device that is not connected: shown greyed out.
        public let connected: Bool

        public init(id: String, title: String, connected: Bool) {
            self.id = id
            self.title = title
            self.connected = connected
        }
    }

    /// The id of the "follow macOS" option.
    public static let systemID = ""

    public let statusLine: String
    public let options: [Option]
    public let selectedID: String

    public init(saved: SavedMicrophone?, devices: [InputDevice], defaultID: AudioObjectID?, selectionFailed: Bool) {
        let defaultName =
            defaultID.flatMap { id in devices.first { $0.id == id } }.map { Self.name($0.name) }
            ?? UIText.localized("keins")
        var options = [
            Option(id: Self.systemID, title: UIText.localized("Wie macOS (aktuell \(defaultName))"), connected: true)
        ]
        options += devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.map {
            Option(id: $0.uid, title: Self.name($0.name), connected: true)
        }
        switch MicrophoneChoice.resolve(saved, in: devices) {
        case .system:
            // Following macOS never shows a fallback marker, even if setting the device failed.
            statusLine = UIText.localized("Mikrofon: \(defaultName)")
            selectedID = Self.systemID
        case .chosen(let device):
            statusLine =
                selectionFailed
                ? UIText.localized("Mikrofon: \(defaultName) · \(Self.name(device.name)) nicht verfügbar")
                : UIText.localized("Mikrofon: \(Self.name(device.name))")
            selectedID = device.uid
        case .fallback:
            // `.fallback` only arises with a saved choice.
            let saved = saved!
            statusLine = UIText.localized("Mikrofon: \(defaultName) · \(Self.name(saved.name)) nicht verbunden")
            options.append(
                Option(
                    id: saved.uid, title: UIText.localized("\(Self.name(saved.name)) (nicht verbunden)"),
                    connected: false))
            selectedID = saved.uid
        }
        self.options = options
    }

    /// The choice to store for a menu id; the greyed-out missing device keeps the current choice.
    public static func choice(for id: String, devices: [InputDevice], current: SavedMicrophone?) -> SavedMicrophone? {
        if id == systemID { return nil }
        if let device = devices.first(where: { $0.uid == id }) {
            return SavedMicrophone(uid: device.uid, name: device.name)
        }
        return current
    }

    private static func name(_ name: String) -> String {
        name.isEmpty ? UIText.localized("Mikrofon ohne Namen") : name
    }
}
