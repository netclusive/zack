import CoreAudio
import Foundation

/// Reports once that an input device went away. An engine with a set device posts no configuration change when that
/// device is unplugged; it runs on silently on another device. Event-driven: the device is checked whenever its
/// listener fires, and once right after listening starts, so a loss before the listener was in place is not missed.
final class DeviceLossWatch: @unchecked Sendable {
    private let lock = NSLock()
    private let device: AudioObjectID
    private let isAlive: @Sendable (AudioObjectID) -> Bool
    private let onLoss: @Sendable () -> Void
    /// Keeps the listener; `cancel` releases it.
    private var subscription: AnyObject?
    /// Reported or cancelled: nothing is reported any more.
    private var finished = false

    /// `listen` starts listening on `device` with the given handler and returns what keeps the listener; `onLoss` may
    /// run on the creating thread (device already gone) or wherever the listener runs.
    init(
        device: AudioObjectID, listen: (AudioObjectID, @escaping @Sendable () -> Void) -> AnyObject,
        isAlive: @escaping @Sendable (AudioObjectID) -> Bool, onLoss: @escaping @Sendable () -> Void
    ) {
        self.device = device
        self.isAlive = isAlive
        self.onLoss = onLoss
        // The handler holds the watch weakly: the watch owns the listener, not the other way round.
        let subscription = listen(device) { [weak self] in self?.check() }
        lock.withLock { self.subscription = subscription }
        check()
    }

    /// Stops reporting and releases the listener outside the lock: removing it may wait for a running handler.
    func cancel() {
        let subscription = lock.withLock { () -> AnyObject? in
            finished = true
            defer { self.subscription = nil }
            return self.subscription
        }
        withExtendedLifetime(subscription) {}
    }

    /// Reports the loss if the device no longer lives, at most once. The device is read outside the lock.
    private func check() {
        guard lock.withLock({ !finished }), !isAlive(device) else { return }
        let first = lock.withLock { () -> Bool in
            defer { finished = true }
            return !finished
        }
        if first { onLoss() }
    }
}
