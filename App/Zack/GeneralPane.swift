import SwiftUI
import ZackCore
import ZackDesktop

/// "Allgemein": language, hotkey, microphone readiness, login item, the AI cleanup, the term check and the playback
/// pause.
struct GeneralPane: View {
    let model: AppModel

    var body: some View {
        Form {
            Section {
                Picker(
                    "Sprache",
                    selection: Binding(get: { model.dictationLanguage }, set: { model.setDictationLanguage($0) })
                ) {
                    ForEach(DictationLanguage.allCases, id: \.self) { language in
                        Text(language.title).tag(language)
                    }
                }
                Picker("Taste", selection: Binding(get: { model.hotkey }, set: { model.setHotkey($0) })) {
                    ForEach(HotkeyKey.allCases, id: \.self) { key in
                        Text(key.title).tag(key)
                    }
                }
                Picker(
                    selection: Binding(get: { model.microphoneReadiness }, set: { model.setMicrophoneReadiness($0) })
                ) {
                    ForEach(MicrophoneReadiness.allCases, id: \.self) { readiness in
                        Text(readiness.title).tag(readiness)
                    }
                } label: {
                    Text("Mikrofon bereithalten")
                    Text(
                        "Hält das Mikrofon nach einem Diktat offen, damit der Anfang nicht fehlt. Solange es offen ist, zeigt macOS den orangen Punkt."
                    )
                }
                Toggle(
                    "Beim Anmelden starten",
                    isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }
            Section {
                Toggle(
                    isOn: Binding(get: { model.aiCleanup && model.cleanerAvailable }, set: { model.setAICleanup($0) })
                ) {
                    Text("KI-Glättung bei Selbstkorrekturen")
                    Text(
                        "Enthält ein Diktat eine Selbstkorrektur wie ‚Montag, nein, Dienstag‘, glättet Apples Modell den Satz auf diesem Mac."
                    )
                }
                .disabled(!model.cleanerAvailable)
                if let hint = model.cleanerHint {
                    Text(hint)
                        .foregroundStyle(.secondary)
                }
                Toggle(isOn: Binding(get: { model.termCheckOn }, set: { model.setTermCheck($0) })) {
                    Text("Fachbegriffe gegenprüfen")
                    Text(
                        "Ist Zack bei einem Wort unsicher, hört Whisper die Aufnahme mit den Begriffen aus dem Wörterbuch noch einmal ab und ersetzt nur dieses Wort. Lädt dafür einmalig ein Modell (\(WhisperSetup.downloadSize)). Alles bleibt auf diesem Mac."
                    )
                }
                .disabled(!model.termCheckAvailable)
                if case .downloading(let fraction) = model.termCheckState {
                    ProgressView(value: fraction) {
                        Text("Modell wird heruntergeladen")
                    } currentValueLabel: {
                        Text(fraction, format: .percent.precision(.fractionLength(0)))
                    }
                }
                ForEach(model.termCheckHints, id: \.self) { hint in
                    Text(hint)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Toggle(isOn: Binding(get: { model.pausePlayback }, set: { model.setPausePlayback($0) })) {
                    Text("Wiedergabe beim Diktieren pausieren")
                    Text("Hält Spotify während eines Diktats an und setzt es danach fort.")
                }
            }
        }
        .formStyle(.grouped)
    }
}
