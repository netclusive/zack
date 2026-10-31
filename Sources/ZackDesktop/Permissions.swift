@preconcurrency import AVFoundation
import ApplicationServices
import CoreGraphics
import Foundation

public enum PermissionState: Equatable, Sendable {
    case granted
    case denied
    case notDetermined
}

/// Privacy permissions; System Settings decides, the app can only check and ask.
public enum Permissions {
    public static func microphone() -> PermissionState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    /// Shows the system dialog once; later calls return the stored answer.
    public static func requestMicrophone() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// Accessibility: reading the hotkey in other apps and sending Cmd+V.
    public static func accessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Shows the system hint that leads to System Settings; returns at once.
    public static func promptAccessibility() {
        // Value of `kAXTrustedCheckOptionPrompt`; the imported global is not concurrency-safe in Swift 6.
        _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    /// Input Monitoring, only asked for if the hotkey needs it (see `needsInputMonitoring`).
    public static func inputMonitoring() -> Bool {
        CGPreflightListenEventAccess()
    }

    public static func requestInputMonitoring() {
        _ = CGRequestListenEventAccess()
    }

    /// True if global key events need Input Monitoring besides Accessibility.
    public static let needsInputMonitoring = false

    public enum Pane: String, Sendable {
        case microphone = "Privacy_Microphone"
        case accessibility = "Privacy_Accessibility"
        case inputMonitoring = "Privacy_ListenEvent"
    }

    /// Deep link into System Settings > Privacy & Security.
    public static func settingsURL(_ pane: Pane) -> URL {
        URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane.rawValue)")!
    }
}
