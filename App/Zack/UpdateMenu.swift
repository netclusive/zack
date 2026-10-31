import SwiftUI
import ZackUpdate

/// "Update auf 1.x.y …" below the status line while an update waits that Sparkle did not show itself; a click opens
/// Sparkle's window with the changes.
struct UpdateAvailableRow: View {
    let updater: Updater

    var body: some View {
        if case .available = updater.menuState, let title = updater.menuState.title {
            Button(title) { updater.checkForUpdates() }
        }
    }
}

/// Update block above the setup entries; builds without a feed show only a note.
struct UpdateMenuSection: View {
    @Bindable var updater: Updater

    var body: some View {
        Divider()
        if updater.menuState == .unavailable, let title = updater.menuState.title {
            Text(title)
        } else {
            Button("Nach Updates suchen …") { updater.checkForUpdates() }
                .disabled(!updater.canCheck)
            Toggle("Automatisch nach Updates suchen", isOn: $updater.automaticallyChecks)
            Toggle("Updates automatisch installieren", isOn: $updater.automaticallyInstalls)
                .disabled(!updater.automaticallyChecks)
        }
    }
}
