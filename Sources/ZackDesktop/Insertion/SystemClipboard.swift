import AppKit

/// `NSPasteboard` adapter; the general pasteboard in the app, a private named one in tests.
@MainActor
public final class SystemClipboard: Clipboard {
    private let pasteboard: NSPasteboard
    private static let transient = NSPasteboard.PasteboardType(Inserter.transientType)
    private static let concealed = NSPasteboard.PasteboardType(Inserter.concealedType)

    public init(_ pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    public var changeCount: Int { pasteboard.changeCount }

    public var access: ClipboardAccess {
        switch pasteboard.accessBehavior {
        case .alwaysAllow: .alwaysAllow
        case .alwaysDeny: .alwaysDeny
        default: .ask
        }
    }

    /// A concealed item (password) is recorded as its marker type only, without any data, so no secret is kept.
    public func snapshot() -> ClipboardSnapshot {
        let items = (pasteboard.pasteboardItems ?? []).map { item in
            if item.types.contains(Self.concealed) {
                return ClipboardSnapshot.Item(entries: [.init(type: Inserter.concealedType, data: Data())])
            }
            return ClipboardSnapshot.Item(
                entries: item.types.compactMap { type in
                    item.data(forType: type).map { ClipboardSnapshot.Entry(type: type.rawValue, data: $0) }
                })
        }
        return ClipboardSnapshot(items: items)
    }

    @discardableResult
    public func write(_ text: String, transient: Bool) -> Int {
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        if transient { item.setData(Data(), forType: Self.transient) }
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    /// Writes the saved items back, marked transient so clipboard managers do not record them a second time.
    public func restore(_ snapshot: ClipboardSnapshot) {
        pasteboard.clearContents()
        // Concealed items carry no data and are never written back.
        let items = snapshot.items.filter { !$0.entries.contains { $0.type == Inserter.concealedType } }.map { saved in
            let item = NSPasteboardItem()
            for entry in saved.entries {
                item.setData(entry.data, forType: NSPasteboard.PasteboardType(entry.type))
            }
            return item
        }
        guard let first = items.first else { return }
        first.setData(Data(), forType: Self.transient)
        pasteboard.writeObjects(items)
    }
}
