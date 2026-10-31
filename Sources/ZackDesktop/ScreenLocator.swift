import AppKit
import ApplicationServices

/// Finds the screen of the active window, so the pill appears where the user looks.
public enum ScreenLocator {
    /// Index of the screen with the largest part of `window`. `window` is in Accessibility coordinates (origin at
    /// the top left of the primary screen, y down), `screens` in AppKit coordinates (origin bottom left, y up).
    public static func screenIndex(window: CGRect, screens: [CGRect], primaryHeight: CGFloat) -> Int? {
        let flipped = CGRect(
            x: window.minX, y: primaryHeight - window.maxY, width: window.width, height: window.height)
        let areas = screens.map { screen -> CGFloat in
            let overlap = screen.intersection(flipped)
            return overlap.isNull ? 0 : overlap.width * overlap.height
        }
        guard let best = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[best] > 0 else { return nil }
        return best
    }

    /// Screen of the frontmost app's focused window; the primary screen if unknown (no Accessibility, no window).
    @MainActor
    public static func activeScreen() -> NSScreen? {
        let screens = NSScreen.screens
        guard let primary = screens.first else { return nil }
        guard let window = focusedWindowFrame(),
            let index = screenIndex(window: window, screens: screens.map(\.frame), primaryHeight: primary.frame.height)
        else { return primary }
        return screens[index]
    }

    /// Frame of the focused window of the frontmost app, in Accessibility coordinates.
    @MainActor
    static func focusedWindowFrame() -> CGRect? {
        guard AXIsProcessTrusted(), let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else {
            return nil
        }
        let app = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
            let window, CFGetTypeID(window) == AXUIElementGetTypeID()
        else { return nil }
        let element = window as! AXUIElement
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
            let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin),
            AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }
}
