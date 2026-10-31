import CoreFoundation
import Testing

@testable import ZackDesktop

struct CursorMemoryTests {
    let terminal = FrontApp(bundleID: "com.apple.Terminal", pid: 42)
    let field = FocusElement(pid: 42, reference: "field-1" as CFString)
    let other = FocusElement(pid: 42, reference: "field-2" as CFString)

    @Test func remembersTheLastInsertAtTheSamePlace() {
        let memory = CursorMemory()
        memory.remember("Der Server läuft.", app: terminal, element: field)
        #expect(memory.text(app: terminal, element: field) == "Der Server läuft.")
        // Element unknown on either side: the process decides.
        #expect(memory.text(app: terminal, element: nil) == "Der Server läuft.")
    }

    @Test func otherElementOrAppGetsNothing() {
        let memory = CursorMemory()
        memory.remember("Der Server läuft.", app: terminal, element: field)
        #expect(memory.text(app: terminal, element: other) == nil)
        #expect(memory.text(app: FrontApp(bundleID: "com.apple.TextEdit", pid: 7), element: nil) == nil)
        #expect(memory.text(app: nil, element: nil) == nil)
    }

    @Test func clickBetweenDictationsDropsTheMemory() {
        let memory = CursorMemory()
        memory.remember("Der Server läuft.", app: terminal, element: field)
        memory.forget()
        #expect(memory.text(app: terminal, element: field) == nil)
    }

    @Test func keepsOnlyTheTrimmedTail() {
        let memory = CursorMemory()
        memory.remember("Zeile eins.\nZeile zwei.", app: terminal, element: nil)
        #expect(memory.text(app: terminal, element: nil) == "\nZeile zwei.")
    }
}
