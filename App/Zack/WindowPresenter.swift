import AppKit
import SwiftUI
import ZackDesktop

/// Settings and about windows, managed here so they can open at launch and from the pill.
@MainActor
final class WindowPresenter {
    private var windows: [String: NSWindow] = [:]
    private var observers: [String: [any NSObjectProtocol]] = [:]

    /// `onClose` runs when the user closes the window; a later `show` opens it again. With `size` the window can be
    /// resized and minimised and starts at `size`; `minSize`, used only with `size`, is its smallest content size.
    /// `onBecomeKey` runs every time the window becomes key.
    func show(
        id: String, title: String, size: CGSize? = nil, minSize: CGSize? = nil,
        onClose: (@MainActor () -> Void)? = nil, onBecomeKey: (@MainActor () -> Void)? = nil,
        content: () -> some View
    ) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
        } else {
            let hosting = NSHostingController(rootView: content())
            let window: NSWindow
            if let size {
                window = SizedWindow.make(hosting: hosting, size: size, minSize: minSize)
            } else {
                window = NSWindow(contentViewController: hosting)
                window.styleMask = [.titled, .closable]
            }
            window.title = title
            window.isReleasedWhenClosed = false
            window.center()
            windows[id] = window
            var tokens = [
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification, object: window, queue: .main
                ) { [weak self] _ in
                    // Delivered on the main queue (`queue: .main`).
                    MainActor.assumeIsolated {
                        self?.forget(id)
                        onClose?()
                    }
                }
            ]
            if let onBecomeKey {
                tokens.append(
                    NotificationCenter.default.addObserver(
                        forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
                    ) { _ in
                        // Delivered on the main queue (`queue: .main`).
                        MainActor.assumeIsolated { onBecomeKey() }
                    })
            }
            observers[id] = tokens
            window.makeKeyAndOrderFront(nil)
        }
        // A menu bar app is not active by itself, and activation is cooperative on macOS 14 and later: a launch
        // from Terminal or Finder may not bring the app forward. Ordering the window front covers that.
        windows[id]?.orderFrontRegardless()
        NSApp.activate()
    }

    /// Renames an open window; does nothing if it is closed.
    func setTitle(_ title: String, id: String) {
        windows[id]?.title = title
    }

    func isOpen(id: String) -> Bool {
        windows[id] != nil
    }

    /// Closes the window if it is open; its close observer forgets it, so the next `show` builds fresh content.
    func close(id: String) {
        windows[id]?.close()
    }

    private func forget(_ id: String) {
        windows[id] = nil
        for observer in observers.removeValue(forKey: id) ?? [] { NotificationCenter.default.removeObserver(observer) }
    }
}
