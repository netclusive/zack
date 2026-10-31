import AppKit
import SwiftUI

/// Setup and about windows, managed here so they can open at launch and from the pill.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]
    private var observers: [String: any NSObjectProtocol] = [:]

    /// `onClose` runs when the user closes the window; a later `show` opens it again.
    func show(id: String, title: String, onClose: (@MainActor () -> Void)? = nil, content: () -> some View) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
        } else {
            let window = NSWindow(contentViewController: NSHostingController(rootView: content()))
            window.title = title
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            windows[id] = window
            observers[id] = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                // Delivered on the main queue (`queue: .main`).
                MainActor.assumeIsolated {
                    self?.forget(id)
                    onClose?()
                }
            }
            window.makeKeyAndOrderFront(nil)
        }
        // A menu bar app is not active by itself, and activation is cooperative on macOS 14 and later: a launch
        // from Terminal or Finder may not bring the app forward. Ordering the window front covers that.
        windows[id]?.orderFrontRegardless()
        NSApp.activate()
    }

    /// Closes the window if it is open; its close observer forgets it, so the next `show` builds fresh content.
    func close(id: String) {
        windows[id]?.close()
    }

    private func forget(_ id: String) {
        windows[id] = nil
        if let observer = observers.removeValue(forKey: id) { NotificationCenter.default.removeObserver(observer) }
    }
}
