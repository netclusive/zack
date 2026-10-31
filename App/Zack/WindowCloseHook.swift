import AppKit
import SwiftUI

extension View {
    /// Runs `action` just before the window showing this view closes, while the view still exists, so ⌘W keeps a
    /// pending draft. Other windows closing (About, updates, sheets, panels) do not trigger it.
    func onWindowWillClose(perform action: @escaping () -> Void) -> some View {
        background(WindowCloseObserver(action: action))
    }
}

/// Empty view that learns its window and observes the close of that window only.
private struct WindowCloseObserver: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> ObservingView {
        let view = ObservingView()
        view.action = action
        return view
    }

    func updateNSView(_ view: ObservingView, context: Context) {
        view.action = action
    }

    final class ObservingView: NSView {
        var action: (() -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self, name: NSWindow.willCloseNotification, object: nil)
            guard let window else { return }
            // A selector observer goes away with the view; no explicit removal needed.
            NotificationCenter.default.addObserver(
                self, selector: #selector(windowWillClose), name: NSWindow.willCloseNotification, object: window)
        }

        /// Posted on the main thread, synchronously during `close()`.
        @objc private func windowWillClose(_ notification: Notification) {
            action?()
        }

        /// Never takes clicks meant for the content in front of it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
