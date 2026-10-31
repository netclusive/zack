import CoreAudio
import Synchronization
import Testing

@testable import ZackDesktop

struct DeviceLossWatchTests {
    /// Stands in for Core Audio: one device whose listener the test fires and whose liveness it sets.
    private final class FakeDevice: Sendable {
        /// What keeps the listener; a test checks that the watch lets go of it.
        final class Subscription: Sendable {}

        private struct State {
            var alive = true
            var listener: (@Sendable () -> Void)?
            var listenedOn: [AudioObjectID] = []
            var checked: [AudioObjectID] = []
            weak var subscription: Subscription?
        }

        private let state = Mutex(State())

        init(alive: Bool = true) {
            state.withLock { $0.alive = alive }
        }

        func listen(_ device: AudioObjectID, _ handler: @escaping @Sendable () -> Void) -> AnyObject {
            let subscription = Subscription()
            state.withLock { state in
                state.listener = handler
                state.listenedOn.append(device)
                state.subscription = subscription
            }
            return subscription
        }

        func isAlive(_ device: AudioObjectID) -> Bool {
            state.withLock { state in
                state.checked.append(device)
                return state.alive
            }
        }

        func unplug() { state.withLock { $0.alive = false } }

        /// Calls the listener as Core Audio would, also after the watch let go of it (a late call).
        func fire() {
            let listener = state.withLock { $0.listener }
            listener?()
        }

        var listenedOn: [AudioObjectID] { state.withLock { $0.listenedOn } }
        var checked: Set<AudioObjectID> { state.withLock { Set($0.checked) } }
        var subscriptionReleased: Bool { state.withLock { $0.subscription == nil } }
    }

    private final class Losses: Sendable {
        private let value = Mutex(0)
        func record() { value.withLock { $0 += 1 } }
        var count: Int { value.withLock { $0 } }
    }

    private func makeWatch(_ device: FakeDevice, _ losses: Losses, id: AudioObjectID = 42) -> DeviceLossWatch {
        DeviceLossWatch(
            device: id, listen: { device.listen($0, $1) }, isAlive: { device.isAlive($0) }, onLoss: { losses.record() })
    }

    @Test func listensOnAndChecksTheDeviceItWatches() {
        let device = FakeDevice()
        let watch = makeWatch(device, Losses(), id: 42)
        device.fire()
        #expect(device.listenedOn == [42])
        #expect(device.checked == [42])
        watch.cancel()
    }

    @Test func aListenerCallWhileTheDeviceLivesReportsNothing() {
        let device = FakeDevice()
        let losses = Losses()
        let watch = makeWatch(device, losses)
        device.fire()
        #expect(losses.count == 0)
        watch.cancel()
    }

    @Test func aDeviceThatWentAwayIsReportedExactlyOnce() {
        let device = FakeDevice()
        let losses = Losses()
        let watch = makeWatch(device, losses)
        device.unplug()
        device.fire()
        device.fire()
        #expect(losses.count == 1)
        watch.cancel()
    }

    @Test func nothingIsReportedAfterCancel() {
        let device = FakeDevice()
        let losses = Losses()
        let watch = makeWatch(device, losses)
        watch.cancel()
        device.unplug()
        device.fire()
        #expect(losses.count == 0)
    }

    @Test func cancelReleasesTheListener() {
        let device = FakeDevice()
        let watch = makeWatch(device, Losses())
        #expect(!device.subscriptionReleased)
        watch.cancel()
        #expect(device.subscriptionReleased)
    }

    @Test func aReleasedWatchReleasesTheListener() {
        let device = FakeDevice()
        var watch: DeviceLossWatch? = makeWatch(device, Losses())
        #expect(watch != nil)
        #expect(!device.subscriptionReleased)
        watch = nil
        #expect(device.subscriptionReleased)
    }

    /// The device may die between the engine start and the listener being in place; no listener call follows then.
    @Test func aDeviceAlreadyGoneWhenTheWatchStartsIsReportedAtOnce() {
        let device = FakeDevice(alive: false)
        let losses = Losses()
        let watch = makeWatch(device, losses)
        #expect(losses.count == 1)
        device.fire()
        #expect(losses.count == 1)
        watch.cancel()
    }
}
