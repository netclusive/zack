import AppKit
import SwiftUI
import ZackDesktop

extension View {
    /// Runs `action` just before the window showing this view closes, while the view still exists, so ⌘W keeps a
    /// pending draft. Other windows closing (About, updates, sheets, panels) do not trigger it.
    func onWindowWillClose(perform action: @escaping () -> Void) -> some View {
        background(WindowObserver(name: NSWindow.willCloseNotification, action: action))
    }

    /// Runs `action` when the window showing this view stops being key, e.g. when another app comes to the front.
    /// Other windows losing key status do not trigger it.
    func onWindowDidResignKey(perform action: @escaping () -> Void) -> some View {
        background(WindowObserver(name: NSWindow.didResignKeyNotification, action: action))
    }
}

/// Puts a `WindowNotificationView` behind the content, which observes one notification of its window only.
private struct WindowObserver: NSViewRepresentable {
    let name: Notification.Name
    let action: () -> Void

    func makeNSView(context: Context) -> WindowNotificationView {
        let view = WindowNotificationView(name: name)
        view.action = action
        return view
    }

    func updateNSView(_ view: WindowNotificationView, context: Context) {
        view.action = action
    }
}
