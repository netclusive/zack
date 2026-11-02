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
                    .mic, UIText.localized("\(time) · noch \(remaining) s"),
                    UIText.localized("Nimmt auf, noch \(remaining) Sekunden"), style: .working, level: level)
            } else {
                self.init(.mic, time, UIText.localized("Nimmt auf, \(time)"), style: .working, level: level)
            }
        case .recognizing:
            self.init(.loader, UIText.localized("Erkenne …"), UIText.localized("Erkenne"), style: .working)
        case .cleaning:
            self.init(.sparkles, UIText.localized("KI glättet …"), UIText.localized("KI glättet"), style: .working)
        case .inserted(.pasted):
            self.init(.check, UIText.localized("Eingefügt"), UIText.localized("Eingefügt"), style: .success)
        case .inserted(.clipboardOnly):
            self.init(.clipboard, UIText.localized("In Zwischenablage"), UIText.localized("In Zwischenablage"))
        case .ruleText(.pasted):
            self.init(
                .check, UIText.localized("Regeltext eingefügt"), UIText.localized("Regeltext eingefügt"),
                style: .success)
        case .ruleText(.clipboardOnly):
            self.init(
                .clipboard, UIText.localized("Regeltext in Zwischenablage"),
                UIText.localized("Regeltext in Zwischenablage"))
        case .failed(let failure):
            switch failure {
            case .nothingHeard:
                self.init(.micOff, UIText.localized("Nichts gehört"), UIText.localized("Nichts gehört"))
            case .modelMissing:
                self.init(
                    .alert, UIText.localized("Modell fehlt · Einrichtung öffnen"),
                    UIText.localized("Modell fehlt, Einrichtung öffnen"), setup: true)
            case .microphoneDenied:
                self.init(
                    .micOff, UIText.localized("Kein Mikrofonzugriff · Einrichtung öffnen"),
                    UIText.localized("Kein Mikrofonzugriff, Einrichtung öffnen"), setup: true)
            case .microphoneUnavailable:
                self.init(
                    .micOff, UIText.localized("Mikrofon nicht verfügbar"), UIText.localized("Mikrofon nicht verfügbar"))
            case .microphoneDisconnected:
                self.init(.micOff, UIText.localized("Mikrofon getrennt"), UIText.localized("Mikrofon getrennt"))
            case .recognitionFailed:
                self.init(
                    .alert, UIText.localized("Erkennung fehlgeschlagen · Menü: Erneut versuchen"),
                    UIText.localized("Erkennung fehlgeschlagen, im Menü erneut versuchen"))
            case .passwordField:
                self.init(
                    .lock, UIText.localized("Passwortfeld · kein Diktat"),
                    UIText.localized("Passwortfeld · kein Diktat"))
            }
        case .notice(let notice):
            switch notice {
            case .passwordFieldNotInserted:
                self.init(
                    .lock, UIText.localized("Passwortfeld · nicht eingefügt"),
                    UIText.localized("Passwortfeld · nicht eingefügt"))
            case .cancelled:
                self.init(.x, UIText.localized("Abgebrochen"), UIText.localized("Abgebrochen"))
            case .noLastDictation:
                self.init(.alert, UIText.localized("Noch kein Diktat"), UIText.localized("Noch kein Diktat"))
            case .noCleanedVersion:
                self.init(.alert, UIText.localized("Keine KI-Fassung"), UIText.localized("Keine KI-Fassung"))
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
