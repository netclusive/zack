/// What the pill shows for a dictation state; the app only draws it.
public struct PillContent: Equatable, Sendable {
    /// Lucide icon, by asset name in the app.
    public enum Icon: String, Sendable {
        case mic = "lucide-mic"
        case micOff = "lucide-mic-off"
        case loader = "lucide-loader-circle"
        case sparkles = "lucide-sparkles"
        case check = "lucide-check"
        case clipboard = "lucide-clipboard-check"
        case alert = "lucide-circle-alert"
        case lock = "lucide-lock"
        case x = "lucide-x"
    }

    public enum Style: Sendable {
        /// Blue-to-turquoise gradient while recording and processing.
        case working
        /// Turquoise background, only for inserted text.
        case success
        /// Gray background.
        case neutral
    }

    public var icon: Icon
    public var text: String
    public var style: Style
    /// Level meter value while recording.
    public var level: Float?
    /// A click opens the setup window.
    public var opensSetup: Bool
    /// VoiceOver text: the visible text without symbols.
    public var accessibilityLabel: String

    /// Nil while the pill is hidden.
    public init?(_ state: DictationState) {
        switch state {
        case .idle, .listening:
            return nil
        case .recording(let elapsed, let level):
            let time = Self.time(elapsed)
            if elapsed >= DictationLimits.hint {
                let remaining = max(0, Int((DictationLimits.maximum - elapsed).components.seconds))
                self.init(
                    .mic, "\(time) · noch \(remaining) s", "Nimmt auf, noch \(remaining) Sekunden", style: .working,
                    level: level)
            } else {
                self.init(.mic, time, "Nimmt auf, \(time)", style: .working, level: level)
            }
        case .recognizing:
            self.init(.loader, "Erkenne …", "Erkenne", style: .working)
        case .cleaning:
            self.init(.sparkles, "KI glättet …", "KI glättet", style: .working)
        case .inserted(.pasted):
            self.init(.check, "Eingefügt", "Eingefügt", style: .success)
        case .inserted(.clipboardOnly):
            self.init(.clipboard, "In Zwischenablage", "In Zwischenablage")
        case .ruleText(.pasted):
            self.init(.check, "Regeltext eingefügt", "Regeltext eingefügt", style: .success)
        case .ruleText(.clipboardOnly):
            self.init(.clipboard, "Regeltext in Zwischenablage", "Regeltext in Zwischenablage")
        case .failed(let failure):
            switch failure {
            case .nothingHeard:
                self.init(.micOff, "Nichts gehört", "Nichts gehört")
            case .modelMissing:
                self.init(.alert, "Modell fehlt · Einrichtung öffnen", "Modell fehlt, Einrichtung öffnen", setup: true)
            case .microphoneDenied:
                self.init(
                    .micOff, "Kein Mikrofonzugriff · Einrichtung öffnen", "Kein Mikrofonzugriff, Einrichtung öffnen",
                    setup: true)
            case .microphoneUnavailable:
                self.init(.micOff, "Mikrofon nicht verfügbar", "Mikrofon nicht verfügbar")
            case .microphoneDisconnected:
                self.init(.micOff, "Mikrofon getrennt", "Mikrofon getrennt")
            case .recognitionFailed:
                self.init(
                    .alert, "Erkennung fehlgeschlagen · Menü: Erneut versuchen",
                    "Erkennung fehlgeschlagen, im Menü erneut versuchen")
            case .passwordField:
                self.init(.lock, "Passwortfeld · kein Diktat", "Passwortfeld · kein Diktat")
            }
        case .notice(let notice):
            switch notice {
            case .passwordFieldNotInserted:
                self.init(.lock, "Passwortfeld · nicht eingefügt", "Passwortfeld · nicht eingefügt")
            case .cancelled:
                self.init(.x, "Abgebrochen", "Abgebrochen")
            case .noLastDictation:
                self.init(.alert, "Noch kein Diktat", "Noch kein Diktat")
            case .noCleanedVersion:
                self.init(.alert, "Keine KI-Fassung", "Keine KI-Fassung")
            }
        }
    }

    private init(
        _ icon: Icon, _ text: String, _ label: String, style: Style = .neutral, level: Float? = nil,
        setup: Bool = false
    ) {
        self.icon = icon
        self.text = text
        self.style = style
        self.level = level
        self.opensSetup = setup
        self.accessibilityLabel = label
    }

    /// `m:ss`.
    static func time(_ duration: Duration) -> String {
        let seconds = max(0, Int(duration.components.seconds))
        let minutes = seconds / 60
        let rest = seconds % 60
        return "\(minutes):\(rest < 10 ? "0" : "")\(rest)"
    }
}
