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

/// The manual check; builds without a feed show nothing (the settings window explains it).
struct UpdateMenuSection: View {
    let updater: Updater

    var body: some View {
        if updater.menuState != .unavailable {
            Button("Nach Updates suchen …") { updater.checkForUpdates() }
                .disabled(!updater.canCheck)
        }
    }
}
