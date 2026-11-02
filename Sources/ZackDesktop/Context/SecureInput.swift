import AppKit
import Carbon
import CoreGraphics

/// Secure Event Input (password fields, Terminal "Secure Keyboard Entry"): the system hides key events from other apps.
public enum SecureInput {
    public static func isEnabled() -> Bool {
        IsSecureEventInputEnabled()
    }

    /// Name of the app holding Secure Input, or nil if unknown. For the menu only, never for log lines.
    public static func holderName() -> String? {
        // "kCGSSessionSecureInputPID" is an undocumented key of the session dictionary and may change.
        guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
            let pid = session["kCGSSessionSecureInputPID"] as? Int
        else { return nil }
        return NSRunningApplication(processIdentifier: pid_t(pid))?.localizedName
    }

    /// True if the hotkey does not arrive while Secure Input is on. It does arrive, so this is false. Read by
    /// nothing: the menu line (`SecureInputLine`) is used instead; kept to document the result.
    public static let blocksHotkey = false
}

/// The menu line that tells another app holds Secure Input; nil while it is off.
public enum SecureInputLine {
    public static func text(enabled: Bool, holder: String?) -> String? {
        guard enabled else { return nil }
        guard let holder else { return UIText.localized("Secure Input aktiv") }
        return UIText.localized("Secure Input aktiv · \(holder)")
    }
}
