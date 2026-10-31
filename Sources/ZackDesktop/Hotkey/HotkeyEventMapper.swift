/// The fields of a keyboard event the hotkey needs, decoupled from `NSEvent` for tests.
public struct KeyEventInfo: Equatable, Sendable {
    public enum Kind: Sendable {
        case keyDown
        case flagsChanged
    }

    public var kind: Kind
    public var keyCode: UInt16
    /// `NSEvent.modifierFlags.rawValue`, including the device-dependent low bits.
    public var flags: UInt
    /// `CGEvent` field `.eventSourceUserData`; 0 for events the user typed.
    public var sourceUserData: Int64

    public init(kind: Kind, keyCode: UInt16, flags: UInt, sourceUserData: Int64 = 0) {
        self.kind = kind
        self.keyCode = keyCode
        self.flags = flags
        self.sourceUserData = sourceUserData
    }
}

/// What the user did outside Zack that moves the cursor: a key (code only) or a mouse click.
public enum UserInput: Equatable, Sendable {
    case key(UInt16)
    case click
}

/// Maps keyboard events to `HotkeyInput` for the selected key.
public enum HotkeyEventMapper {
    /// `NSEvent.ModifierFlags`: shift, control, option, command, function.
    static let shift: UInt = 1 << 17
    static let control: UInt = 1 << 18
    static let option: UInt = 1 << 19
    static let command: UInt = 1 << 20
    static let function: UInt = 1 << 23
    /// `NX_DEVICELALTKEYMASK`, `NX_DEVICERALTKEYMASK` (IOKit/hidsystem/IOLLEvent.h).
    static let leftOptionDevice: UInt = 0x20
    static let rightOptionDevice: UInt = 0x40

    /// Tag on the events Zack posts itself (the paste keystroke), carried in `.eventSourceUserData`.
    /// ASCII "ZACK". That the tag survives into a global `NSEvent` monitor is WAHRSCHEINLICH, not verified:
    /// to be checked by hand.
    public static let ownEventMarker: Int64 = 0x5A41_434B

    /// True for events Zack posted itself; the monitor drops them so they never count as "another key".
    public static func isOwn(_ event: KeyEventInfo) -> Bool {
        event.sourceUserData == ownEventMarker
    }

    /// Zack's own global shortcuts, ⌃⌥V (insert last) and ⌃⌥O (rule text): they do not move the cursor.
    public static func isShortcut(_ event: KeyEventInfo) -> Bool {
        guard event.kind == .keyDown,
            [Shortcut.insertLast, .ruleText].contains(where: { $0.keyCode == UInt32(event.keyCode) })
        else { return false }
        return event.flags & control != 0 && event.flags & option != 0
            && event.flags & (command | shift) == 0
    }

    public static func map(_ event: KeyEventInfo, key: HotkeyKey) -> HotkeyInput {
        guard event.kind == .flagsChanged, event.keyCode == key.keyCode else { return .otherKey }
        guard isDown(key, flags: event.flags) else { return .triggerUp }
        // Pressed together with another modifier: a shortcut such as fn+Shift, not a dictation.
        return hasOtherModifiers(key, flags: event.flags) ? .otherKey : .triggerDown
    }

    static func isDown(_ key: HotkeyKey, flags: UInt) -> Bool {
        switch key {
        case .fn: flags & function != 0
        // The option flag stays set while the left key is held, so only the device bit tells the right key.
        case .rightOption: flags & rightOptionDevice != 0
        }
    }

    static func hasOtherModifiers(_ key: HotkeyKey, flags: UInt) -> Bool {
        switch key {
        case .fn: flags & (shift | control | option | command) != 0
        case .rightOption: flags & (shift | control | command | function | leftOptionDevice) != 0
        }
    }
}
