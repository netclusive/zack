import AppKit
import SwiftUI

/// A window the user sizes: SwiftUI content fills it but never resizes it.
public enum SizedWindow {
    /// Titled, closable, resizable and minimisable; starts at `size`, never smaller than `minSize`.
    @MainActor
    public static func make(hosting: NSHostingController<some View>, size: CGSize, minSize: CGSize?) -> NSWindow {
        // As the window's content view, a hosting view sizes the window to its content and resets the minimum size,
        // even without sizing options. Inside a plain view it only fills the window.
        hosting.sizingOptions = []
        let container = NSViewController()
        container.view = NSView(frame: NSRect(origin: .zero, size: size))
        container.addChild(hosting)
        hosting.view.frame = container.view.bounds
        hosting.view.autoresizingMask = [.width, .height]
        container.view.addSubview(hosting.view)
        let window = NSWindow(contentViewController: container)
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.setContentSize(size)
        if let minSize { window.contentMinSize = minSize }
        return window
    }
}
