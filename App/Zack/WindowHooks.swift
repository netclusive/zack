import AppKit
import SwiftUI

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

/// Empty view that learns its window and observes one notification of that window only.
private struct WindowObserver: NSViewRepresentable {
    let name: Notification.Name
    let action: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView(name: name)
        view.action = action
        return view
    }

    func updateNSView(_ view: ObservingView, context: Context) {
        view.action = action
    }

    final class ObservingView: NSView {
        let name: Notification.Name
        var action: (() -> Void)?

        init(name: Notification.Name) {
            self.name = name
            super.init(frame: .zero)
        }

        /// Never loaded from a nib.
        @available(*, unavailable)
        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
            guard let window else { return }
            // A selector observer goes away with the view; no explicit removal needed.
            NotificationCenter.default.addObserver(self, selector: #selector(windowChanged), name: name, object: window)
        }

        /// Posted on the main thread, synchronously (for a close, during `close()`).
        @objc private func windowChanged(_ notification: Notification) {
            action?()
        }

        /// Never takes clicks meant for the content in front of it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
