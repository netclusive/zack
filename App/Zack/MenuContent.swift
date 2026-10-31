import AppKit
import SwiftUI
import ZackDesktop
import ZackUpdate

/// Menu bar icon: microphone while recording, alert when setup is missing, otherwise the Zack Z.
struct MenuBarLabel: View {
    let model: AppModel

    var body: some View {
        let status = model.status
        Image(nsImage: Brand.menuBarIcon(MenuBarSymbol(status).rawValue))
            .accessibilityLabel("Zack, \(model.statusTitle)")
    }
}

/// The menu bar menu.
struct MenuContent: View {
    let model: AppModel
    let updater: Updater

    var body: some View {
        Button {
            model.statusClicked()
        } label: {
            Label {
                Text(model.statusTitle)
            } icon: {
                Image(nsImage: Brand.dot(model.status.tone))
            }
        }
        UpdateAvailableRow(updater: updater)
        if let line = model.secureInputLine { Text(line) }
        Text("Erkenner: Parakeet Ultra")
        Text(model.microphoneMenu.statusLine)
        Picker(
            "Mikrofon wählen",
            selection: Binding(get: { model.microphoneMenu.selectedID }, set: { model.setMicrophone($0) })
        ) {
            if let system = model.microphoneMenu.options.first {
                Text(system.title).tag(system.id).disabled(!system.connected)
                Divider()
            }
            ForEach(model.microphoneMenu.options.dropFirst()) { option in
                Text(option.title).tag(option.id).disabled(!option.connected)
            }
        }
        Divider()
        Toggle(
            "KI-Glättung bei Korrekturen",
            isOn: Binding(get: { model.aiCleanup && model.cleanerAvailable }, set: { model.setAICleanup($0) })
        )
        .disabled(!model.cleanerAvailable)
        if let hint = model.cleanerHint { Text(hint) }
        Picker("Taste", selection: Binding(get: { model.hotkey }, set: { model.setHotkey($0) })) {
            ForEach(HotkeyKey.allCases, id: \.self) { key in
                Text(key.title).tag(key)
            }
        }
        Picker(
            "Mikrofon bereithalten",
            selection: Binding(get: { model.microphoneReadiness }, set: { model.setMicrophoneReadiness($0) })
        ) {
            ForEach(MicrophoneReadiness.allCases, id: \.self) { readiness in
                Text(readiness.title).tag(readiness)
            }
        }
        .accessibilityHint(
            "Hält das Mikrofon nach einem Diktat offen, damit der Anfang nicht fehlt. Solange es offen ist, zeigt macOS den orangen Punkt."
        )
        Toggle(
            "Beim Anmelden starten", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
        Divider()
        Button(
            model.shortcutTaken.contains(.insertLast)
                ? "Letztes Diktat einfügen (Kürzel belegt)" : "Letztes Diktat einfügen"
        ) {
            model.insertLast()
        }
        .keyboardShortcut("v", modifiers: [.control, .option])
        .disabled(!model.hasLastText)
        Button(
            model.shortcutTaken.contains(.ruleText)
                ? "Regeltext statt KI-Fassung (Kürzel belegt)" : "Regeltext statt KI-Fassung"
        ) {
            model.replaceWithRuleText()
        }
        .keyboardShortcut("o", modifiers: [.control, .option])
        .disabled(!model.canReplaceWithRuleText)
        Button("Letztes Diktat kopieren") { model.copyLastText() }
            .disabled(!model.hasLastText)
        if model.canRetry {
            Button("Erneut versuchen") { model.retry() }
        }
        Button("Wörterbuch bearbeiten …") { model.openVocabulary() }
        Button("Textbausteine bearbeiten …") { model.openSnippets() }
        if let app = model.codeModeApp {
            Toggle(
                app.match == .prefix ? "Code-Modus in \(app.name) (über code-apps.txt)" : "Code-Modus in \(app.name)",
                isOn: Binding(get: { app.match != .none }, set: { _ in model.toggleCodeMode() })
            )
            .disabled(app.match == .prefix)
        }
        Button("Code-Apps bearbeiten …") { model.openCodeApps() }
        UpdateMenuSection(updater: updater)
        Divider()
        Button("Einstellungen …") { model.showSettings() }
            .keyboardShortcut(",")
        Button("Über Zack") { model.showAbout() }
        #if DEBUG
            DebugMenu(model: model)
        #endif
        Divider()
        Button("Zack beenden") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}

#if DEBUG
    /// Debug: paste test with a chosen restore delay; shows the clipboard access setting.
    struct DebugMenu: View {
        let model: AppModel

        var body: some View {
            Menu("Debug") {
                Text("Zwischenablage-Zugriff: \(model.clipboardAccess)")
                Text(
                    "Secure Input: \(SecureInput.isEnabled() ? "an" : "aus") · \(SecureInput.holderName() ?? "unbekannt")"
                )
                ForEach([100, 250, 500, 1_000], id: \.self) { milliseconds in
                    Button("Einfügetest in 3 s, D = \(milliseconds) ms") {
                        model.debugInsertTest(delay: .milliseconds(milliseconds))
                    }
                }
                Button("Kontext lesen in 3 s") { model.debugReadContext() }
                Button("Esc für 10 s registrieren (K2)") { model.debugRegisterEscape() }
                Button("Bearbeiten-Test …") { model.debugShowEditingSpike() }
                Section("Abschnittstest") { Button("Eintrag im Abschnitt") {} }
                Picker("Titel \(Date.now.formatted(date: .omitted, time: .standard))", selection: .constant(0)) {
                    Text("Option").tag(0)
                }
            }
        }
    }
#endif
