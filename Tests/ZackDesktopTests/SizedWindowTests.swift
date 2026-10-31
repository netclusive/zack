import AppKit
import SwiftUI
import Testing

@testable import ZackDesktop

@MainActor
struct SizedWindowTests {
    @Test func layoutKeepsSizeAndMinimumSize() {
        _ = NSApplication.shared
        // Content that would like more height than the window has.
        let hosting = NSHostingController(rootView: Text("Wörterbuch").frame(minHeight: 900))
        let window = SizedWindow.make(
            hosting: hosting, size: CGSize(width: 720, height: 480), minSize: CGSize(width: 640, height: 420))
        defer { window.close() }
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.3))

        #expect(window.contentMinSize == CGSize(width: 640, height: 420))
        #expect(window.contentRect(forFrameRect: window.frame).size == CGSize(width: 720, height: 480))
    }
}
