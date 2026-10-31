import AppKit
import Foundation
import Testing

@testable import ZackDesktop

/// The real adapter on a private named pasteboard: no system dialog, the general clipboard stays untouched.
@MainActor
struct SystemClipboardTests {
    @Test func snapshotAndRestoreKeepAllItemsAndTypes() throws {
        let named = NSPasteboard(name: NSPasteboard.Name("com.netclusive.zack.tests.\(UUID().uuidString)"))
        defer { named.releaseGlobally() }
        let clipboard = SystemClipboard(named)
        let first = NSPasteboardItem()
        first.setString("Text", forType: .string)
        first.setData(Data([1, 2, 3]), forType: NSPasteboard.PasteboardType("com.example.custom"))
        let second = NSPasteboardItem()
        second.setString("https://example.com", forType: .URL)
        named.clearContents()
        named.writeObjects([first, second])
        let saved = clipboard.snapshot()

        let own = clipboard.write("Diktat", transient: true)
        #expect(own == named.changeCount)
        #expect(named.string(forType: .string) == "Diktat")
        let marker = NSPasteboard.PasteboardType(Inserter.transientType)
        #expect(named.pasteboardItems?.first?.types.contains(marker) == true)

        clipboard.restore(saved)
        let restored = try #require(named.pasteboardItems)
        #expect(restored.count == 2)
        #expect(restored[0].string(forType: .string) == "Text")
        #expect(restored[0].data(forType: NSPasteboard.PasteboardType("com.example.custom")) == Data([1, 2, 3]))
        #expect(restored[1].string(forType: .URL) == "https://example.com")
    }

    @Test func emptyClipboardRestoresToEmpty() {
        let named = NSPasteboard(name: NSPasteboard.Name("com.netclusive.zack.tests.\(UUID().uuidString)"))
        defer { named.releaseGlobally() }
        let clipboard = SystemClipboard(named)
        named.clearContents()
        let saved = clipboard.snapshot()
        clipboard.write("Diktat", transient: true)
        clipboard.restore(saved)
        #expect(named.pasteboardItems?.isEmpty ?? true)
    }

    @Test func concealedItemsAreNeitherCopiedNorRestored() {
        let named = NSPasteboard(name: NSPasteboard.Name("com.netclusive.zack.tests.\(UUID().uuidString)"))
        defer { named.releaseGlobally() }
        let clipboard = SystemClipboard(named)
        let secret = NSPasteboardItem()
        secret.setString("hunter2", forType: .string)
        secret.setData(Data(), forType: NSPasteboard.PasteboardType(Inserter.concealedType))
        named.clearContents()
        named.writeObjects([secret])

        let saved = clipboard.snapshot()
        let entries = saved.items.flatMap(\.entries)
        #expect(entries.contains { $0.type == Inserter.concealedType })
        #expect(!entries.contains { $0.data == Data("hunter2".utf8) })
        #expect(!entries.contains { $0.type == NSPasteboard.PasteboardType.string.rawValue })

        clipboard.write("Diktat", transient: true)
        clipboard.restore(saved)
        #expect(named.pasteboardItems?.isEmpty ?? true)
        #expect(named.string(forType: .string) == nil)
    }
}
