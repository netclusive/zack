import Foundation
import Observation
import Sparkle
import os

/// Sparkle's standard updater behind a small observable state for the menu. Without a configuration (local and
/// third-party builds) no Sparkle updater exists and the menu only says so.
@MainActor
@Observable
public final class Updater {
    public private(set) var menuState: UpdateMenuState
    /// A manual check is possible; false before the start and during any update session, which includes a background
    /// download and the time the "Update auf …" reminder waits, so "Nach Updates suchen …" is greyed out then.
    public private(set) var canCheck = false
    /// Sparkle's automatic check setting. The menu writes it; Sparkle's opt-in prompt on the second launch changes it
    /// too, and the observation below copies that back.
    public var automaticallyChecks: Bool {
        didSet {
            // Only real differences reach Sparkle, so copying Sparkle's own changes back never writes again.
            guard let sparkle = controller?.updater, sparkle.automaticallyChecksForUpdates != automaticallyChecks
            else { return }
            sparkle.automaticallyChecksForUpdates = automaticallyChecks
            syncFromSparkle()
        }
    }
    /// Sparkle downloads updates in the background and installs them when Zack quits; needs automatic checks.
    public var automaticallyInstalls: Bool {
        didSet {
            guard let sparkle = controller?.updater, sparkle.automaticallyDownloadsUpdates != automaticallyInstalls
            else { return }
            sparkle.automaticallyDownloadsUpdates = automaticallyInstalls
            // Sparkle ignores the value while automatic checks are off; show what it holds.
            syncFromSparkle()
        }
    }

    @ObservationIgnored private let controller: SPUStandardUpdaterController?
    /// Sparkle references its user driver delegate weakly.
    @ObservationIgnored private let userDriverDelegate: UserDriverDelegate?
    @ObservationIgnored fileprivate let isDictating: @MainActor () -> Bool
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var started = false
    @ObservationIgnored private let logger = Logger(subsystem: "com.netclusive.zack", category: "update")

    /// Sparkle reads feed and key from the Info dictionary itself; `configuration` only decides whether it runs.
    public init(configuration: UpdateConfiguration?, isDictating: @escaping @MainActor () -> Bool) {
        self.isDictating = isDictating
        guard configuration != nil else {
            controller = nil
            userDriverDelegate = nil
            menuState = .unavailable
            automaticallyChecks = false
            automaticallyInstalls = false
            return
        }
        let delegate = UserDriverDelegate()
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: nil, userDriverDelegate: delegate)
        self.controller = controller
        userDriverDelegate = delegate
        menuState = .idle
        automaticallyChecks = controller.updater.automaticallyChecksForUpdates
        automaticallyInstalls = controller.updater.automaticallyDownloadsUpdates
        delegate.updater = self
    }

    /// Starts Sparkle once; it asks for permission on the second launch and then checks once a day.
    public func start() {
        guard !started else { return }
        started = true
        guard let sparkle = controller?.updater else {
            logger.notice("disabled: no configuration")
            return
        }
        do {
            // Not the controller's startUpdater(): it would show a developer alert and log the full error text.
            try sparkle.start()
        } catch {
            let error = error as NSError
            logger.error("start failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
            menuState = .unavailable
            canCheck = false
            return
        }
        logger.notice("started")
        // KVO keeps the menu in step with Sparkle, including its own opt-in prompt.
        let observe: @Sendable (SPUUpdater, NSKeyValueObservedChange<Bool>) -> Void = { [weak self] _, _ in
            Self.onMain { self?.syncFromSparkle() }
        }
        observations = [
            sparkle.observe(\.canCheckForUpdates, options: [.initial, .new], changeHandler: observe),
            sparkle.observe(\.automaticallyChecksForUpdates, options: [.initial, .new], changeHandler: observe),
            sparkle.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new], changeHandler: observe),
        ]
    }

    /// Opens Sparkle's window: a manual check, or the update that waits in the menu.
    public func checkForUpdates() {
        guard started, let controller, menuState != .unavailable else { return }
        controller.checkForUpdates(nil)
    }

    private func syncFromSparkle() {
        guard let sparkle = controller?.updater else { return }
        if canCheck != sparkle.canCheckForUpdates { canCheck = sparkle.canCheckForUpdates }
        if automaticallyChecks != sparkle.automaticallyChecksForUpdates {
            automaticallyChecks = sparkle.automaticallyChecksForUpdates
        }
        if automaticallyInstalls != sparkle.automaticallyDownloadsUpdates {
            automaticallyInstalls = sparkle.automaticallyDownloadsUpdates
        }
    }

    /// KVO calls back on the thread that changed the value; Sparkle changes these on the main thread.
    private nonisolated static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            Task { @MainActor in body() }
        }
    }

    fileprivate func remind(version: String) {
        menuState = .available(version: version)
    }

    fileprivate func clearReminder() {
        if case .available = menuState { menuState = .idle }
    }
}

/// Gentle reminders, as Sparkle requires for an app without a Dock icon: Sparkle shows a scheduled update only in
/// immediate focus (Zack launched recently or the system was idle for some time) and never during a dictation, so its
/// window cannot take the paste target; otherwise the menu offers the update.
/// `@preconcurrency` is sound: SPUStandardUserDriver is NS_SWIFT_UI_ACTOR, so calls arrive on main; off main they trap.
@MainActor
private final class UserDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    weak var updater: Updater?

    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        UpdatePresentation.sparkleShowsScheduledUpdate(
            immediateFocus: immediateFocus, dictating: updater?.isDictating() ?? false)
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        updater?.remind(version: update.displayVersionString)
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        updater?.clearReminder()
    }

    func standardUserDriverWillFinishUpdateSession() {
        updater?.clearReminder()
    }
}
