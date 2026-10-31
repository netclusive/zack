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
        Picker(
            model.microphoneMenu.statusLine,
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
        Section("Letztes Diktat") {
            Button(model.shortcutTaken.contains(.insertLast) ? "Einfügen (Kürzel belegt)" : "Einfügen") {
                model.insertLast()
            }
            .keyboardShortcut("v", modifiers: [.control, .option])
            .disabled(!model.hasLastText)
            Button(
                model.shortcutTaken.contains(.ruleText)
                    ? "Ohne KI-Glättung einfügen (Kürzel belegt)" : "Ohne KI-Glättung einfügen"
            ) {
                model.replaceWithRuleText()
            }
            .keyboardShortcut("o", modifiers: [.control, .option])
            .disabled(!model.canReplaceWithRuleText)
            Button("Kopieren") { model.copyLastText() }
                .disabled(!model.hasLastText)
            if model.canRetry {
                Button("Erneut versuchen") { model.retry() }
            }
        }
        Divider()
        if let app = model.codeModeApp {
            Toggle(
                app.match == .prefix ? "Code-Modus in \(app.name) (über Code-Apps-Liste)" : "Code-Modus in \(app.name)",
                isOn: Binding(get: { app.match != .none }, set: { _ in model.toggleCodeMode() })
            )
            .disabled(app.match == .prefix)
        }
        Button("Wörterbuch …") { model.showSettings(.vocabulary) }
        Button("Textbausteine …") { model.showSettings(.snippets) }
        Divider()
        UpdateMenuSection(updater: updater)
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
