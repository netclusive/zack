import Foundation

/// Every clipboard item with all its types, so a restore is lossless.
public struct ClipboardSnapshot: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public var type: String
        public var data: Data

        public init(type: String, data: Data) {
            self.type = type
            self.data = data
        }
    }

    public struct Item: Equatable, Sendable {
        public var entries: [Entry]

        public init(entries: [Entry]) {
            self.entries = entries
        }
    }

    public var items: [Item]

    public init(items: [Item]) {
        self.items = items
    }
}

/// Setting under System Settings > Privacy & Security > Paste from Other Apps (macOS 15.4+).
public enum ClipboardAccess: Equatable, Sendable {
    /// The system may ask before Zack reads the clipboard.
    case ask
    case alwaysAllow
    case alwaysDeny
}

/// The general pasteboard, behind a protocol so insertion can be tested without touching the user's clipboard.
@MainActor
public protocol Clipboard: AnyObject {
    var changeCount: Int { get }
    var access: ClipboardAccess { get }
    func snapshot() -> ClipboardSnapshot
    /// Replaces the contents with `text`; returns the change count after writing.
    @discardableResult func write(_ text: String, transient: Bool) -> Int
    func restore(_ snapshot: ClipboardSnapshot)
}

/// Sends Cmd+V to the frontmost app.
@MainActor
public protocol KeystrokePoster: AnyObject {
    func postPaste()
}
