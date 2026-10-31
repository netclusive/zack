import CoreGraphics
import Testing

@testable import ZackDesktop

struct ShortcutReleaseTests {
    @Test func releasedNeedsTheKeyAndBothModifiersUp() {
        let v = UInt16(Shortcut.insertLast.keyCode)
        let up: (UInt16) -> Bool = { _ in false }
        #expect(ShortcutRelease.isReleased(.insertLast, keyIsDown: up, flags: []))
        #expect(!ShortcutRelease.isReleased(.insertLast, keyIsDown: { $0 == v }, flags: []))
        #expect(!ShortcutRelease.isReleased(.insertLast, keyIsDown: up, flags: .maskControl))
        #expect(!ShortcutRelease.isReleased(.insertLast, keyIsDown: up, flags: .maskAlternate))
        #expect(ShortcutRelease.isReleased(.insertLast, keyIsDown: up, flags: .maskShift))
        let o = UInt16(Shortcut.ruleText.keyCode)
        #expect(!ShortcutRelease.isReleased(.ruleText, keyIsDown: { $0 == o }, flags: []))
        #expect(ShortcutRelease.isReleased(.ruleText, keyIsDown: { $0 == v }, flags: []))
    }

    @Test func waitEndsOnceTheKeysAreUp() async {
        var checks = 0
        var sleeps = 0
        let released = await ShortcutRelease.waitUntilReleased(
            polls: 10, sleep: { sleeps += 1 },
            isReleased: {
                checks += 1
                return checks > 3
            })
        #expect(released)
        #expect(sleeps == 3)
    }

    @Test func waitGivesUpAtTheLimit() async {
        var sleeps = 0
        let released = await ShortcutRelease.waitUntilReleased(polls: 5, sleep: { sleeps += 1 }, isReleased: { false })
        #expect(!released)
        #expect(sleeps == 5)
    }
}
