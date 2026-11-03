import AppKit
import Testing

@testable import ZackDesktop

@MainActor
struct WindowNotificationViewTests {
    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.titled, .closable],
            backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    private func observer(_ name: Notification.Name, in window: NSWindow, calls: Counter) -> WindowNotificationView {
        let view = WindowNotificationView(name: name)
        view.action = { calls.increment() }
        window.contentView?.addSubview(view)
        return view
    }

    /// Regression (e8f0ccf): the settings window losing key status saves pending edits; other windows do not count.
    @Test func resignKeyRunsTheActionForItsOwnWindowOnly() {
        let window = makeWindow()
        let other = makeWindow()
        let calls = Counter()
        _ = observer(NSWindow.didResignKeyNotification, in: window, calls: calls)

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: other)
        #expect(calls.value == 0)
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(calls.value == 1)
    }

    /// Regression (e8f0ccf): ⌘W and quitting close the window; the action runs during the close, while the view exists.
    @Test func closingTheWindowRunsTheActionDuringTheClose() {
        let window = makeWindow()
        let calls = Counter()
        _ = observer(NSWindow.willCloseNotification, in: window, calls: calls)

        window.close()
        #expect(calls.value == 1)
    }

    @Test func aViewTakenOutOfItsWindowObservesNothing() {
        let window = makeWindow()
        let calls = Counter()
        let view = observer(NSWindow.didResignKeyNotification, in: window, calls: calls)

        view.removeFromSuperview()
        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)
        #expect(calls.value == 0)
    }

    @Test func theViewNeverTakesClicks() {
        let view = WindowNotificationView(name: NSWindow.didResignKeyNotification)
        view.frame = NSRect(x: 0, y: 0, width: 50, height: 50)
        #expect(view.hitTest(NSPoint(x: 10, y: 10)) == nil)
    }
}
