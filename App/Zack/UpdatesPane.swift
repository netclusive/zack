import SwiftUI
import ZackUpdate

/// "Updates": Sparkle's switches, a manual check and the privacy note; builds without a feed show only a note.
struct UpdatesPane: View {
    let updater: Updater?

    var body: some View {
        Form {
            if let updater, updater.menuState != .unavailable {
                UpdateSwitches(updater: updater)
            } else {
                Text("Updates gibt es nur in offiziellen Builds.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct UpdateSwitches: View {
    @Bindable var updater: Updater

    var body: some View {
        Section {
            Toggle("Automatisch nach Updates suchen", isOn: $updater.automaticallyChecks)
            Toggle("Updates automatisch installieren", isOn: $updater.automaticallyInstalls)
                .disabled(!updater.automaticallyChecks)
            HStack {
                Spacer()
                Button("Jetzt suchen") { updater.checkForUpdates() }
                    .disabled(!updater.canCheck)
            }
        } footer: {
            Text(
                "Die Suche läuft nur nach Zustimmung, einmal am Tag. Feed und Downloads kommen von GitHub (GitHub Inc., USA); jede Anfrage überträgt die IP-Adresse und den User-Agent ‚Zack/<Version> Sparkle/<Version>‘."
            )
        }
    }
}
