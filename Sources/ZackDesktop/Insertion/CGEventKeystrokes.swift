import AppKit
import CoreGraphics

/// Posts Cmd+V as HID events; needs Accessibility.
@MainActor
public final class CGEventKeystrokes: KeystrokePoster {
    /// `kVK_ANSI_V` (HIToolbox Events.h): the V position, also on German layouts.
    static let vKey: CGKeyCode = 0x09

    public init() {}

    public func postPaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Create both events first: if either fails, nothing is posted, so no key stays pressed.
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: Self.vKey, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: Self.vKey, keyDown: false)
        else { return }
        for event in [down, up] {
            event.flags = .maskCommand
            event.setIntegerValueField(.eventSourceUserData, value: HotkeyEventMapper.ownEventMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// Bundle ID of the frontmost app, for the per-app restore delay; never logged.
    public static func frontmostBundleID() -> String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }
}
