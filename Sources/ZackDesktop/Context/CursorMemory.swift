import Synchronization

/// The tail of the last inserted text, for apps that give no text before the cursor.
public final class CursorMemory: Sendable {
    private struct Entry {
        let pid: Int32
        let element: FocusElement?
        let text: String
    }

    private let entry = Mutex<Entry?>(nil)

    public init() {}

    /// Without an app there is no place to attach it, so nothing is kept.
    public func remember(_ inserted: String, app: FrontApp?, element: FocusElement?) {
        guard let app else { return }
        let kept = Entry(pid: app.pid, element: element, text: ContextResolver.trim(inserted))
        entry.withLock { $0 = kept }
    }

    public func forget() {
        entry.withLock { $0 = nil }
    }

    /// The same process, and the same element when both sides know one.
    public func text(app: FrontApp?, element: FocusElement?) -> String? {
        guard let app else { return nil }
        return entry.withLock { stored in
            guard let stored, stored.pid == app.pid else { return nil }
            if let a = stored.element, let b = element, a != b { return nil }
            return stored.text
        }
    }
}
