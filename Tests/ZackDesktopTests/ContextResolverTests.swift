import CoreFoundation
import Testing

@testable import ZackDesktop

struct ContextResolverTests {
    let field = FocusElement(pid: 42, reference: "field-1" as CFString)

    @Test func readRangeCoversAtMostFiveHundredUnitsBeforeTheCursor() {
        #expect(ContextResolver.readRange(before: 1_200) == TextRange(location: 700, length: 500))
        #expect(ContextResolver.readRange(before: 30) == TextRange(location: 0, length: 30))
        #expect(ContextResolver.readRange(before: 0) == TextRange(location: 0, length: 0))
    }

    @Test func trimKeepsTheCurrentLineWithItsNewline() {
        #expect(ContextResolver.trim("Erste Zeile.\nZweite Zeile, und") == "\nZweite Zeile, und")
        #expect(ContextResolver.trim("Gruß\r\n") == "\r\n")
        #expect(ContextResolver.trim("ohne Umbruch") == "ohne Umbruch")
    }

    @Test func trimCapsAtFiveHundredCharacters() {
        let long = String(repeating: "a", count: 800)
        #expect(ContextResolver.trim(long).count == 500)
    }

    /// A read that started in the middle of a surrogate pair yields U+FFFD first; it must not reach the rules.
    @Test func trimDropsBrokenFirstCharacter() {
        #expect(ContextResolver.trim("\u{FFFD}ist gut") == "ist gut")
    }

    @Test func accessibilityTextWinsOverMemory() {
        let snapshot = FocusSnapshot(element: field, textBeforeCursor: "Ich glaube,")
        #expect(
            ContextResolver.resolve(snapshot, memory: "Hallo.") == ResolvedContext(text: "Ich glaube,", source: .ax))
    }

    @Test func emptyFieldIsKnownText() {
        let snapshot = FocusSnapshot(element: field, selection: TextRange(location: 0, length: 0), textBeforeCursor: "")
        #expect(ContextResolver.resolve(snapshot, memory: nil) == ResolvedContext(text: "", source: .ax))
    }

    /// VS Code reports "" for a line with text; clearing a real field takes keys, which drop the memory.
    @Test func memoryWinsOverEmptyAccessibilityText() {
        let snapshot = FocusSnapshot(element: field, selection: TextRange(location: 0, length: 0), textBeforeCursor: "")
        #expect(
            ContextResolver.resolve(snapshot, memory: "Der Server läuft.")
                == ResolvedContext(text: "Der Server läuft.", source: .memory))
    }

    @Test func memoryFillsInWhenTheAppGivesNoText() {
        #expect(
            ContextResolver.resolve(FocusSnapshot(element: field), memory: "Hallo.")
                == ResolvedContext(text: "Hallo.", source: .memory))
        #expect(ContextResolver.resolve(.unknown, memory: nil) == ResolvedContext(text: nil, source: .none))
    }
}
