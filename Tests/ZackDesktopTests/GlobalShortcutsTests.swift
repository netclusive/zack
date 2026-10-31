import Carbon
import Testing

@testable import ZackDesktop

struct GlobalShortcutsTests {
    @Test func keysAndModifiers() {
        #expect(Shortcut.insertLast.keyCode == UInt32(kVK_ANSI_V))
        #expect(Shortcut.ruleText.keyCode == UInt32(kVK_ANSI_O))
        #expect(Shortcut.cancel.keyCode == UInt32(kVK_Escape))
        #expect(Shortcut.insertLast.carbonModifiers == UInt32(controlKey | optionKey))
        #expect(Shortcut.ruleText.carbonModifiers == UInt32(controlKey | optionKey))
        #expect(Shortcut.cancel.carbonModifiers == 0)
        #expect(Shortcut.allCases.map(\.title) == ["⌃⌥V", "⌃⌥O", "Esc"])
    }
}
