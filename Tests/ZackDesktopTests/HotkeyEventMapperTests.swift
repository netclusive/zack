import Testing

@testable import ZackDesktop

struct HotkeyEventMapperTests {
    typealias Mapper = HotkeyEventMapper

    func flags(_ keyCode: UInt16, _ flags: UInt) -> KeyEventInfo {
        KeyEventInfo(kind: .flagsChanged, keyCode: keyCode, flags: flags)
    }

    @Test func fnDownAndUp() {
        #expect(Mapper.map(flags(0x3F, Mapper.function), key: .fn) == .triggerDown)
        #expect(Mapper.map(flags(0x3F, 0), key: .fn) == .triggerUp)
    }

    @Test func fnWithArrowIsAnotherKey() {
        // fn+Up is Page Up: a key down that carries the function flag.
        let pageUp = KeyEventInfo(kind: .keyDown, keyCode: 0x74, flags: Mapper.function)
        #expect(Mapper.map(pageUp, key: .fn) == .otherKey)
        let arrow = KeyEventInfo(kind: .keyDown, keyCode: 0x7E, flags: Mapper.function)
        #expect(Mapper.map(arrow, key: .fn) == .otherKey)
    }

    @Test func fnTogetherWithCommandIsAShortcut() {
        #expect(Mapper.map(flags(0x3F, Mapper.function | Mapper.command), key: .fn) == .otherKey)
    }

    @Test func rightOptionUsesTheDeviceBit() {
        let option = Mapper.option
        #expect(Mapper.map(flags(0x3D, option | Mapper.rightOptionDevice), key: .rightOption) == .triggerDown)
        #expect(Mapper.map(flags(0x3D, 0), key: .rightOption) == .triggerUp)
    }

    @Test func rightOptionReleasedWhileLeftOptionHeld() {
        // The option flag stays set for the left key, the right device bit is gone.
        let event = flags(0x3D, Mapper.option | Mapper.leftOptionDevice)
        #expect(Mapper.map(event, key: .rightOption) == .triggerUp)
    }

    @Test func rightOptionWithLeftOptionHeldIsAShortcut() {
        let event = flags(0x3D, Mapper.option | Mapper.leftOptionDevice | Mapper.rightOptionDevice)
        #expect(Mapper.map(event, key: .rightOption) == .otherKey)
    }

    @Test func leftOptionIsNotTheTrigger() {
        #expect(Mapper.map(flags(0x3A, Mapper.option | Mapper.leftOptionDevice), key: .rightOption) == .otherKey)
    }

    @Test func rightOptionWithLetterIsAnotherKey() {
        // Right Option + L types "@" on a German layout; the dictation must not start.
        let letter = KeyEventInfo(kind: .keyDown, keyCode: 0x25, flags: Mapper.option | Mapper.rightOptionDevice)
        #expect(Mapper.map(letter, key: .rightOption) == .otherKey)
    }

    @Test func fnIsIgnoredAsTriggerWhenRightOptionIsSelected() {
        #expect(Mapper.map(flags(0x3F, Mapper.function), key: .rightOption) == .otherKey)
    }

    // Zack's own Cmd+V must not cancel a held dictation.

    @Test func eventsCarryingZacksMarkerAreOwn() {
        let paste = KeyEventInfo(
            kind: .keyDown, keyCode: 0x09, flags: Mapper.command, sourceUserData: Mapper.ownEventMarker)
        #expect(Mapper.isOwn(paste))
    }

    @Test func ruleAndInsertShortcutsAreRecognised() {
        let both = Mapper.control | Mapper.option
        for code: UInt16 in [0x09, 0x1F] {
            #expect(Mapper.isShortcut(KeyEventInfo(kind: .keyDown, keyCode: code, flags: both)))
        }
        #expect(!Mapper.isShortcut(KeyEventInfo(kind: .keyDown, keyCode: 0x09, flags: 0)))
        #expect(!Mapper.isShortcut(KeyEventInfo(kind: .keyDown, keyCode: 0x09, flags: Mapper.command | Mapper.option)))
        #expect(!Mapper.isShortcut(KeyEventInfo(kind: .keyDown, keyCode: 0x09, flags: both | Mapper.shift)))
        #expect(!Mapper.isShortcut(KeyEventInfo(kind: .keyDown, keyCode: 0x09, flags: both | Mapper.command)))
        #expect(!Mapper.isShortcut(KeyEventInfo(kind: .keyDown, keyCode: 0x00, flags: both)))
        #expect(!Mapper.isShortcut(KeyEventInfo(kind: .keyDown, keyCode: 0x0F, flags: both)))
        #expect(!Mapper.isShortcut(KeyEventInfo(kind: .flagsChanged, keyCode: 0x09, flags: both)))
    }

    @Test func otherEventsAreNotOwn() {
        #expect(!Mapper.isOwn(KeyEventInfo(kind: .keyDown, keyCode: 0x09, flags: Mapper.command)))
        #expect(!Mapper.isOwn(KeyEventInfo(kind: .keyDown, keyCode: 0x09, flags: 0, sourceUserData: 42)))
        #expect(Mapper.ownEventMarker != 0)
    }
}
