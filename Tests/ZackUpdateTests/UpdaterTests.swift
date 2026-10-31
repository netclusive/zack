import Testing

@testable import ZackUpdate

/// Only the path without configuration: it creates no Sparkle updater, so nothing checks or downloads in tests.
@MainActor
struct UpdaterTests {
    @Test func missingConfigurationLeavesUpdatesUnavailable() {
        let updater = Updater(configuration: nil, isDictating: { false })
        #expect(updater.menuState == .unavailable)
        #expect(!updater.canCheck)

        updater.start()
        updater.checkForUpdates()
        #expect(updater.menuState == .unavailable)
        #expect(!updater.canCheck)
    }
}
