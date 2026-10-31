import CoreGraphics

/// ⌃⌥V and ⌃⌥O act once their keys are up: Zack's own Cmd+V while V was still held pasted nothing in TextEdit and
/// Safari.
public enum ShortcutRelease {
    public static func isReleased(_ shortcut: Shortcut, keyIsDown: (UInt16) -> Bool, flags: CGEventFlags) -> Bool {
        !keyIsDown(UInt16(shortcut.keyCode)) && flags.intersection([.maskControl, .maskAlternate]).isEmpty
    }

    /// The physical keys, as the HID system sees them.
    public static func isReleased(_ shortcut: Shortcut) -> Bool {
        isReleased(
            shortcut, keyIsDown: { CGEventSource.keyState(.hidSystemState, key: CGKeyCode($0)) },
            flags: CGEventSource.flagsState(.hidSystemState))
    }

    /// Checks before every poll; after `polls` waits it reports the last check, and the caller acts anyway. Runs on
    /// the caller's actor, so the closures need not be sendable.
    public static func waitUntilReleased(
        polls: Int, isolation: isolated (any Actor)? = #isolation, sleep: () async -> Void, isReleased: () -> Bool
    ) async -> Bool {
        for _ in 0..<polls {
            if isReleased() { return true }
            await sleep()
        }
        return isReleased()
    }
}
