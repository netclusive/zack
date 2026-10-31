import AppKit
import os

/// Reads the push-to-talk key in every app with listen-only event monitors; keys always reach their target app.
@MainActor
public final class HotkeyMonitor {
    public var key: HotkeyKey {
        didSet { reset() }
    }

    /// Every key except Zack's own and its shortcuts, and every click in another app; never logged.
    public var onInput: (@MainActor (UserInput) -> Void)?

    private let onAction: @MainActor (HotkeyAction) -> Void
    private var machine = HotkeyStateMachine()
    private var monitors: [Any] = []
    private var tick: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.netclusive.zack", category: "hotkey")

    public init(key: HotkeyKey, onAction: @escaping @MainActor (HotkeyAction) -> Void) {
        self.key = key
        self.onAction = onAction
    }

    /// Global monitors see other apps' events, local ones Zack's own windows. Neither can swallow an event.
    public func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                Self.deliver(Self.info(event)) { [weak self] info, onMainThread in
                    self?.handle(info, onMainThread: onMainThread)
                }
            })
        {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                Self.deliver(Self.info(event)) { [weak self] info, onMainThread in
                    self?.handle(info, onMainThread: onMainThread)
                }
                return event
            })
        {
            monitors.append(local)
        }
        // Clicks in Zack's own windows are not reported: a global monitor only sees other apps.
        if let clicks = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown],
            handler: { [weak self] _ in
                Self.deliverClick { [weak self] in self?.onInput?(.click) }
            })
        {
            monitors.append(clicks)
        }
    }

    public func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        reset()
    }

    /// The fields the mapper needs, read on the delivering thread; the event itself stays there.
    nonisolated private static func info(_ event: NSEvent) -> KeyEventInfo {
        let kind: KeyEventInfo.Kind = event.type == .keyDown ? .keyDown : .flagsChanged
        return KeyEventInfo(
            kind: kind, keyCode: event.keyCode, flags: event.modifierFlags.rawValue,
            sourceUserData: event.cgEvent?.getIntegerValueField(.eventSourceUserData) ?? 0)
    }

    /// Runs `body` on the main actor: directly on the main thread, otherwise queued in order on the main queue.
    /// Delivery has been observed on the main thread only; the queue hop stays as a safeguard.
    nonisolated private static func deliver(
        _ info: KeyEventInfo, to body: @escaping @MainActor @Sendable (KeyEventInfo, Bool) -> Void
    ) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body(info, true) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { body(info, false) } }
        }
    }

    nonisolated private static func deliverClick(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { body() }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
        }
    }

    private func reset() {
        tick?.cancel()
        tick = nil
        machine = HotkeyStateMachine()
    }

    private func handle(_ info: KeyEventInfo, onMainThread: Bool) {
        if !onMainThread { logger.debug("hotkey event delivered off the main thread") }
        // Zack's own paste keystroke is not the user pressing another key.
        guard !HotkeyEventMapper.isOwn(info) else { return }
        if info.kind == .keyDown, !HotkeyEventMapper.isShortcut(info) { onInput?(.key(info.keyCode)) }
        apply(HotkeyEventMapper.map(info, key: key))
    }

    private func apply(_ input: HotkeyInput) {
        guard let action = machine.handle(input, at: .now) else { return }
        // Action names only, never which other key was pressed.
        logger.debug("hotkey \(String(describing: action), privacy: .public)")
        tick?.cancel()
        if action == .begin {
            tick = Task { [weak self] in
                try? await Task.sleep(for: HotkeyStateMachine.holdThreshold)
                guard !Task.isCancelled else { return }
                self?.apply(.tick)
            }
        }
        onAction(action)
    }
}
