import AppKit
import SwiftUI
import ZackDesktop

/// The pill (variant A): a floating panel at the bottom of the active window's screen that never takes focus.
@MainActor
final class PillPanelController {
    private let panel: NSPanel
    private let host: PillHostingView
    private let signposts: Signposts
    private let onSetup: () -> Void
    private var content: PillContent?

    init(signposts: Signposts, onSetup: @escaping () -> Void) {
        self.signposts = signposts
        self.onSetup = onSetup
        host = PillHostingView(rootView: PillView(content: nil, onSetup: onSetup))
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 40), styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = host
    }

    /// Shows the window once, invisibly, so the first real pill does not pay for the first window display.
    func prepare() {
        let size = render(PillContent(.recording(elapsed: .zero, level: 0)))
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        place(size: size, appearing: true)
        panel.orderFrontRegardless()
        panel.display()
        // Undo on the next main-queue turn, unless update(_:) has taken over by then.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.content == nil else { return }
            self.panel.orderOut(nil)
            self.host.rootView = PillView(content: nil, onSetup: self.onSetup)
        }
    }

    func update(_ state: DictationState) {
        guard let next = PillContent(state) else {
            panel.orderOut(nil)
            content = nil
            return
        }
        let previous = content
        content = next
        let size = render(next)
        panel.ignoresMouseEvents = !next.opensSetup
        place(size: size, appearing: previous == nil)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        if previous == nil { signposts.endPill() }
        // VoiceOver hears state changes, not every second of the recording time.
        if previous?.icon != next.icon {
            NSAccessibility.post(
                element: panel, notification: .announcementRequested,
                userInfo: [
                    .announcement: next.accessibilityLabel,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ])
        }
    }

    /// Measures the pill, then pins it to whole points (`PillGeometry`).
    private func render(_ content: PillContent?) -> NSSize {
        host.rootView = PillView(content: content, onSetup: onSetup)
        let size = PillGeometry.size(fitting: host.fittingSize)
        host.rootView = PillView(content: content, onSetup: onSetup, size: size)
        return size
    }

    /// Bottom center of the active screen when appearing; afterwards only the width changes around the center.
    /// The frame stays on whole points, like the size from `render`.
    private func place(size: NSSize, appearing: Bool) {
        var frame = panel.frame
        var midX = frame.midX
        if appearing, let screen = ScreenLocator.activeScreen() {
            midX = screen.visibleFrame.midX
            frame.origin.y = (screen.visibleFrame.minY + 72).rounded()
        }
        frame.origin.x = PillGeometry.originX(centeredAt: midX, width: size.width)
        frame.size = size
        panel.setFrame(frame, display: true)
    }
}

/// A click on the pill must count although the panel never becomes key (non-activating).
final class PillHostingView: NSHostingView<PillView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct PillView: View {
    let content: PillContent?
    let onSetup: () -> Void
    /// Whole-point size from `PillPanelController.render`; nil while measuring.
    var size: CGSize?

    static func fill(_ style: PillContent.Style) -> AnyShapeStyle {
        switch style {
        case .working: AnyShapeStyle(Brand.pillGradient)
        case .success: AnyShapeStyle(Brand.turquoise)
        case .neutral: AnyShapeStyle(Brand.gray)
        }
    }

    var body: some View {
        if let content {
            HStack(spacing: 8) {
                Image(content.icon.rawValue)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 16, height: 16)
                if let level = content.level { LevelMeter(level: level) }
                Text(content.text)
                    .font(.system(size: 13, weight: .medium))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(width: size?.width, height: size?.height)
            .background(Capsule().fill(Self.fill(content.style)))
            .contentShape(Capsule())
            .onTapGesture { if content.opensSetup { onSetup() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(content.accessibilityLabel)
            .accessibilityAddTraits(content.opensSetup ? .isButton : [])
        }
    }
}

/// Five bars, the middle one the tallest.
struct LevelMeter: View {
    let level: Float
    static let weights: [Float] = [0.5, 0.8, 1, 0.8, 0.5]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.weights.indices, id: \.self) { index in
                Capsule()
                    .frame(width: 3, height: CGFloat(4 + 12 * min(1, level * Self.weights[index] * 1.4)))
            }
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
