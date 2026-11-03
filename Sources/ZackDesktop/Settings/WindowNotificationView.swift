import AppKit

/// Empty view that learns its window and runs `action` for one notification of that window only; the app's SwiftUI
/// window hooks put it behind their content.
public final class WindowNotificationView: NSView {
    public let name: Notification.Name
    public var action: (() -> Void)?

    public init(name: Notification.Name) {
        self.name = name
        super.init(frame: .zero)
    }

    /// Never loaded from a nib.
    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override public func viewDidMoveToWindow() {
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
    override public func hitTest(_ point: NSPoint) -> NSView? { nil }
}
