import AppKit
import Testing

@testable import ZackDesktop

@MainActor
struct AppActivationObserverTests {
    /// The workspace posts the classic notification; the typed message must carry the same app.
    @Test func reportsTheActivatedAppFromTheWorkspaceNotification() async {
        let center = NotificationCenter()
        var activated: [pid_t] = []
        let observer = AppActivationObserver(center: center) { activated.append($0.processIdentifier) }

        center.post(
            name: NSWorkspace.didActivateApplicationNotification, object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        // Delivery may hop to the main actor; give it one turn.
        await Task.yield()
        withExtendedLifetime(observer) {}

        #expect(activated == [NSRunningApplication.current.processIdentifier])
    }

    @Test func ignoresOtherNotifications() async {
        let center = NotificationCenter()
        var activated: [pid_t] = []
        let observer = AppActivationObserver(center: center) { activated.append($0.processIdentifier) }

        center.post(
            name: NSWorkspace.didDeactivateApplicationNotification, object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: NSRunningApplication.current])
        await Task.yield()
        withExtendedLifetime(observer) {}

        #expect(activated.isEmpty)
    }
}
