import AppKit

/// Reports each app that becomes active, through the workspace's typed activation message.
@MainActor
public final class AppActivationObserver {
    private let token: NotificationCenter.ObservationToken

    /// `center` is the workspace's own unless a test passes another one.
    public init(
        center: NotificationCenter = NSWorkspace.shared.notificationCenter,
        onActivate: @escaping @MainActor (NSRunningApplication) -> Void
    ) {
        token = center.addObserver(for: NSWorkspace.DidActivateApplicationMessage.self) { message in
            onActivate(message.application)
        }
    }
}
