import SwiftUI
import ZackDesktop

/// Setup pane of the settings window: opens at the first start and whenever something is missing.
struct SetupView: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            microphone
            SetupRow(
                title: String(localized: "Bedienungshilfen"),
                detail: String(
                    localized: "Für das Einfügen mit Cmd+V und den Abbruch mit anderen Tasten, etwa fn + Pfeil."),
                done: model.accessibility
            ) {
                Button("Systemeinstellungen öffnen") { model.openSettings(.accessibility) }
                    .accessibilityLabel("Bedienungshilfen-Einstellungen öffnen")
                    .accessibilityInputLabels(["Systemeinstellungen öffnen", "Bedienungshilfen-Einstellungen öffnen"])
            }
            if Permissions.needsInputMonitoring {
                SetupRow(
                    title: String(localized: "Eingabeüberwachung"),
                    detail: String(localized: "Damit Zack die Taste auch in anderen Apps erkennt."),
                    done: model.inputMonitoring
                ) {
                    Button("Systemeinstellungen öffnen") { model.openSettings(.inputMonitoring) }
                }
            }
            recognitionModel
            SetupRow(
                title: "Apple Intelligence",
                detail: model.cleanerHint ?? String(localized: "Verfügbar für die KI-Glättung bei Korrekturen."),
                done: model.cleanerAvailable
            ) {
                EmptyView()
            }
            if let error = model.setupError {
                Label {
                    Text(error)
                } icon: {
                    StatusIcon(name: "lucide-circle-alert", tone: .yellow)
                }
            }
            HStack {
                Spacer()
                Button("Erneut prüfen") { model.refresh() }
            }
        }
        .padding(24)
    }

    private var microphone: some View {
        SetupRow(title: String(localized: "Mikrofon"), detail: microphoneDetail, done: model.microphone == .granted) {
            switch model.microphone {
            case .granted: EmptyView()
            case .notDetermined: Button("Erlauben") { model.requestMicrophone() }
            case .denied:
                Button("Systemeinstellungen öffnen") { model.openSettings(.microphone) }
                    .accessibilityLabel("Mikrofon-Einstellungen öffnen")
                    .accessibilityInputLabels(["Systemeinstellungen öffnen", "Mikrofon-Einstellungen öffnen"])
            }
        }
    }

    private var microphoneDetail: String {
        switch model.microphone {
        case .granted: String(localized: "Erlaubt. Audio bleibt auf diesem Mac.")
        case .notDetermined: String(localized: "Zack fragt einmal nach dem Zugriff.")
        case .denied: String(localized: "Abgelehnt. In den Systemeinstellungen erlauben.")
        }
    }

    private var recognitionModel: some View {
        VStack(alignment: .leading, spacing: 6) {
            SetupRow(
                title: String(localized: "Spracherkennung Parakeet Ultra"), detail: modelDetail,
                done: model.modelStatus == .ready && !model.modelLoadFailed
            ) {
                switch model.modelStatus {
                case .ready:
                    if model.modelLoadFailed {
                        Button("Erneut versuchen") { model.retryModelLoad() }
                    }
                case .adoptable: Button("Übernehmen") { model.adoptModel() }
                case .missing:
                    if let progress = model.downloadProgress {
                        ProgressView(value: progress)
                            .frame(width: 120)
                            .accessibilityLabel("Modell wird geladen")
                    } else {
                        Button("Laden") { model.downloadModel() }
                    }
                }
            }
            if model.modelStatus == .missing {
                Text(
                    "Größe \(ModelSetup.downloadSize). Quelle: Hugging Face (USA); übertragen wird nur die IP-Adresse. Lizenz: CC BY 4.0."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 30)
            }
        }
    }

    private var modelDetail: String {
        switch model.modelStatus {
        case .ready:
            model.modelLoaded
                ? String(localized: "Bereit.")
                : model.modelLoadFailed
                    ? String(localized: "Modell konnte nicht geladen werden.")
                    : String(localized: "Vorhanden, wird geladen …")
        case .adoptable: String(localized: "Eine Kopie aus dem Messstand liegt vor und wird verschoben, ohne Download.")
        case .missing: String(localized: "Noch nicht vorhanden.")
        }
    }
}

/// One line of the setup window: state icon, text, action.
struct SetupRow<Action: View>: View {
    let title: String
    let detail: String
    let done: Bool
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            StatusIcon(name: done ? "lucide-check" : "lucide-circle-alert", tone: done ? .green : .yellow)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(done ? "erledigt" : "offen")
            Spacer()
            action()
        }
    }
}

/// Lucide icon in a status color (at least 3:1, `Brand.statusColor`); decorative, the text beside it carries the
/// meaning.
struct StatusIcon: View {
    let name: String
    let tone: AppStatus.Tone

    var body: some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .frame(width: 18, height: 18)
            .foregroundStyle(Color(nsColor: Brand.statusColor(tone)))
            .accessibilityHidden(true)
    }
}
