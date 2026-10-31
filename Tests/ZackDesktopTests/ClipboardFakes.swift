import Foundation

@testable import ZackDesktop

/// Clipboard and keystrokes are system interfaces; these stand in for them, `Inserter` itself runs for real.
@MainActor
final class FakeClipboard: Clipboard {
    var changeCount = 0
    var access = ClipboardAccess.alwaysAllow
    var contents = ClipboardSnapshot(items: [])
    private(set) var snapshotCalls = 0
    private(set) var restoreCalls = 0
    /// Writes only; `restore` can run in the background after the first insert.
    private(set) var writes = 0
    private(set) var restored: [ClipboardSnapshot] = []
    private(set) var lastWriteTransient: Bool?

    func snapshot() -> ClipboardSnapshot {
        snapshotCalls += 1
        return contents
    }

    @discardableResult
    func write(_ text: String, transient: Bool) -> Int {
        lastWriteTransient = transient
        writes += 1
        contents = Self.text(text)
        changeCount += 1
        return changeCount
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        restoreCalls += 1
        restored.append(snapshot)
        contents = snapshot
        changeCount += 1
    }

    /// Another app copies something.
    func externalCopy(_ text: String) {
        contents = Self.text(text)
        changeCount += 1
    }

    /// Plain text of the first item, as a target app would paste it.
    var text: String? {
        let entry = contents.items.first?.entries.first { $0.type == Self.plainText }
        return entry.map { String(decoding: $0.data, as: UTF8.self) }
    }

    static let plainText = "public.utf8-plain-text"

    static func text(_ text: String) -> ClipboardSnapshot {
        ClipboardSnapshot(items: [.init(entries: [.init(type: plainText, data: Data(text.utf8))])])
    }
}

/// Stands in for Cmd+V: records what the target app would paste at that moment.
@MainActor
final class FakeKeystrokes: KeystrokePoster {
    private let clipboard: FakeClipboard
    private(set) var pasted: [String] = []

    init(clipboard: FakeClipboard) {
        self.clipboard = clipboard
    }

    func postPaste() {
        pasted.append(clipboard.text ?? "")
    }
}
