import Foundation
import Synchronization
import Testing
import ZackCore

@testable import ZackDesktop

/// Restart of a single-device fake: stop and start, without a device check (`EngineAudioInput` has its own).
extension AudioInput {
    func restart(
        onChunk: @escaping @Sendable ([Float]) -> Void, onEvent: @escaping @Sendable (AudioInputEvent) -> Void
    ) throws {
        stop()
        try start(onChunk: onChunk, onEvent: onEvent)
    }
}

/// Audio source driven by the test instead of a microphone.
final class FakeAudioInput: AudioInput, Sendable {
    private struct State {
        var onChunk: (@Sendable ([Float]) -> Void)?
        var onEvent: (@Sendable (AudioInputEvent) -> Void)?
        /// Handlers of every start, so a test can deliver late callbacks of an earlier start.
        var chunkHandlers: [@Sendable ([Float]) -> Void] = []
        var eventHandlers: [@Sendable (AudioInputEvent) -> Void] = []
        var startCount = 0
        var stopCount = 0
        var failure: ZackError?
        var chunkOnStop: [Float]?
        var gate: StartGate?
        var chunkOnStart: [Float]?
    }

    private let state = Mutex(State())

    func start(
        onChunk: @escaping @Sendable ([Float]) -> Void, onEvent: @escaping @Sendable (AudioInputEvent) -> Void
    ) throws {
        // Waits outside the lock, so the test can still push and inspect while a start is held.
        let gate = state.withLock { state -> StartGate? in
            defer { state.gate = nil }
            return state.gate
        }
        gate?.hold()
        let chunk = try state.withLock { state -> [Float]? in
            if let failure = state.failure { throw failure }
            state.startCount += 1
            state.onChunk = onChunk
            state.onEvent = onEvent
            state.chunkHandlers.append(onChunk)
            state.eventHandlers.append(onEvent)
            defer { state.chunkOnStart = nil }
            return state.chunkOnStart
        }
        if let chunk { onChunk(chunk) }
    }

    /// Keeps the handler: a real tap may deliver one more buffer after stop.
    func stop() {
        let (handler, chunk) = state.withLock { state in
            state.stopCount += 1
            defer { state.chunkOnStop = nil }
            return (state.onChunk, state.chunkOnStop)
        }
        if let chunk { handler?(chunk) }
    }

    /// The next `stop` delivers `samples` before it returns, as a tap buffer that arrives while the engine stops.
    func deliverOnStop(_ samples: [Float]) {
        state.withLock { $0.chunkOnStop = samples }
    }

    /// The next `start` delivers `samples` before it returns, as a tap that fires while the engine starts.
    func deliverOnStart(_ samples: [Float]) {
        state.withLock { $0.chunkOnStart = samples }
    }

    func push(_ samples: [Float]) {
        state.withLock { $0.onChunk }?(samples)
    }

    /// Reports a format change or a lost device, as the engine's configuration-change handler does.
    func emit(_ event: AudioInputEvent) {
        state.withLock { $0.onEvent }?(event)
    }

    /// Delivers a chunk to the handler of an earlier start (0 is the first), as a late tap callback would.
    func push(_ samples: [Float], fromStart index: Int) {
        state.withLock { $0.chunkHandlers[index] }(samples)
    }

    /// Delivers an event to the handler of an earlier start (0 is the first).
    func emit(_ event: AudioInputEvent, fromStart index: Int) {
        state.withLock { $0.eventHandlers[index] }(event)
    }

    /// The next `start` waits until the returned gate opens (at most 2 s, then `timedOut` is set).
    func blockNextStart() -> StartGate {
        let gate = StartGate()
        state.withLock { $0.gate = gate }
        return gate
    }

    func failStarts(with error: ZackError) {
        state.withLock { $0.failure = error }
    }

    func allowStarts() {
        state.withLock { $0.failure = nil }
    }

    var startCount: Int { state.withLock { $0.startCount } }
    var stopCount: Int { state.withLock { $0.stopCount } }
}

/// Holds an audio start until the test opens it; a start nobody opens gives up after 2 s instead of hanging.
final class StartGate: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let expired = Mutex(false)

    func hold() {
        if semaphore.wait(timeout: .now() + 2) == .timedOut { expired.withLock { $0 = true } }
    }

    func open() { semaphore.signal() }

    var timedOut: Bool { expired.withLock { $0 } }
}

final class Counter: Sendable {
    private let count = Mutex(0)

    func increment() {
        count.withLock { $0 += 1 }
    }

    var value: Int { count.withLock { $0 } }
}

/// A clock for `now` closures that only moves when the test says so.
final class ManualNow: Sendable {
    private let value = Mutex(ContinuousClock.now)

    var now: ContinuousClock.Instant { value.withLock { $0 } }

    func advance(by duration: Duration) {
        value.withLock { $0 = $0.advanced(by: duration) }
    }
}

/// One second at 16 kHz of a tone well above the silence limits.
func tone(seconds: Double = 1, amplitude: Float = 0.3) -> [Float] {
    (0..<Int(seconds * 16_000)).map { amplitude * sin(Float($0) * 0.1) }
}

/// Polls `condition` until it holds; real time, at most `limit`.
func eventually(within limit: Duration = .seconds(2), _ condition: @Sendable () async -> Bool) async -> Bool {
    let interval = Duration.milliseconds(5)
    for _ in 0..<Int(limit / interval) {
        if await condition() { return true }
        try? await Task.sleep(for: interval)
    }
    return false
}

/// Polls `condition` from synchronous code until it holds; real time, at most 2 s.
func eventuallyBlocking(_ condition: () -> Bool) -> Bool {
    for _ in 0..<400 {
        if condition() { return true }
        Thread.sleep(forTimeInterval: 0.005)
    }
    return false
}

/// Audio source whose restart is refused, as when the default input moved to another device.
final class RefusingRestartInput: AudioInput, Sendable {
    private let onEvent = Mutex<(@Sendable (AudioInputEvent) -> Void)?>(nil)
    private let restarts = Counter()
    private let starts = Counter()

    func start(
        onChunk: @escaping @Sendable ([Float]) -> Void, onEvent: @escaping @Sendable (AudioInputEvent) -> Void
    ) throws {
        starts.increment()
        self.onEvent.withLock { $0 = onEvent }
    }

    func restart(
        onChunk: @escaping @Sendable ([Float]) -> Void, onEvent: @escaping @Sendable (AudioInputEvent) -> Void
    ) throws {
        restarts.increment()
        throw ZackError.audioFormat
    }

    func stop() {}

    func emit(_ event: AudioInputEvent) {
        onEvent.withLock { $0 }?(event)
    }

    var restartCount: Int { restarts.value }
    var startCount: Int { starts.value }
}
