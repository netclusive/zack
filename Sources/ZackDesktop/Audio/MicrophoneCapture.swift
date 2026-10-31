import Foundation
import Synchronization
import ZackCore

/// Records from an `AudioInput` into memory, with the current level and start timings.
/// Audio never touches the disk. A format change restarts the input and keeps the recording.
///
/// Warm mode ("Mikrofon bereithalten"): after `warmUp` the input stays open between recordings and only a short
/// pre-roll is kept, continuously overwritten; the next `start` begins with it, so nothing is lost while the
/// device wakes up. `release` closes the input. Without `warmUp` the capture behaves exactly as before.
public final class MicrophoneCapture: Sendable {
    /// Measured from `start`. A warm start with a pre-roll has audio at once: `firstChunk` is zero, and
    /// `firstSound` is zero if the pre-roll already holds sound, otherwise the time to the first non-silent live
    /// chunk. A cold start (or an empty pre-roll) measures both on the live chunks, as before. `warm` tells a warm
    /// start with an empty pre-roll apart from a cold one.
    public struct Timings: Equatable, Sendable {
        /// From `start` to the first chunk.
        public var firstChunk: Duration?
        /// From `start` to the first chunk that is not silent (`EngineLimits`).
        public var firstSound: Duration?
        /// Length of the pre-roll the recording starts with; zero for a cold start.
        public var preRoll: Duration
        /// The recording began on an input that was already open (even if the pre-roll was empty).
        public var warm: Bool

        public init(
            firstChunk: Duration? = nil, firstSound: Duration? = nil, preRoll: Duration = .zero, warm: Bool = false
        ) {
            self.firstChunk = firstChunk
            self.firstSound = firstSound
            self.preRoll = preRoll
            self.warm = warm
        }
    }

    private struct Recording {
        var samples: [Float] = []
        var startedAt: ContinuousClock.Instant
        var timings = Timings()
        var onInterruption: @Sendable () -> Void
        /// Generation of the recording's first start: chunks from it onwards belong to this recording.
        var firstGeneration: Int
    }

    private struct State {
        /// Nil outside a recording.
        var recording: Recording?
        var level: Float = 0
        /// Timings of the last recording, still readable after `stop`.
        var lastTimings = Timings()
        /// Counts input starts, restarts included; never reset, so callbacks of an older start can be told apart.
        var generation = 0
        /// The input runs: started and not yet stopped.
        var inputOpen = false
        /// Warm mode: keep the input open after a recording; idle chunks go into `preRoll`.
        var warm = false
        var preRoll = PreRoll(duration: .zero)
        /// Set during a recording when its device was lost or the input changed: a warm input opens again
        /// when the recording ends. Ignored while cold; the next open clears it.
        var reopen = false
    }

    private let input: any AudioInput
    private let now: @Sendable () -> ContinuousClock.Instant
    private let state = Mutex(State())
    /// Start, stop, cancel, restarts and reopens run one after the other here, so the input never sees two at once.
    private let control = DispatchQueue(label: "com.netclusive.zack.capture")

    public init(
        input: any AudioInput = EngineAudioInput(),
        now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }
    ) {
        self.input = input
        self.now = now
    }

    /// Starts recording; earlier samples are dropped. A warm input continues and the recording begins with its
    /// pre-roll. `onInterruption` fires when the device is lost. It runs on the capture's private control queue.
    /// Only `level`, `timings`, `isWarm` and `inputChanged()` are safe to call from it; every other member
    /// (`start`, `stop`, `cancel`, `warmUp`, `release`) waits on that queue and would deadlock. Hand off to another
    /// task instead.
    public func start(onInterruption: @escaping @Sendable () -> Void = {}) throws {
        try control.sync { try startRecording(at: now(), onInterruption: onInterruption) }
    }

    /// Like `start`, but returns at once, so the caller never waits for the audio engine. The start runs on the
    /// control queue: a later `stop`, `cancel`, `warmUp` or `release` waits for it. Timings count from this call.
    /// `onFailure` runs on the control queue if the input cannot start; the rules of `onInterruption` apply to it.
    /// `signposts` marks how long the input start blocks ("micstart"); a warm start has none.
    public func startInBackground(
        signposts: Signposts? = nil, onInterruption: @escaping @Sendable () -> Void = {},
        onFailure: @escaping @Sendable (any Error) -> Void
    ) {
        let startedAt = now()
        control.async { [self] in
            do {
                try startRecording(at: startedAt, onInterruption: onInterruption, signposts: signposts)
            } catch {
                onFailure(error)
            }
        }
    }

    /// Stops and returns everything recorded since `start`. A warm input stays open.
    public func stop() -> AudioClip {
        control.sync {
            let keepOpen = state.withLock { $0.warm && $0.inputOpen }
            // A closing input stops first, as without warm mode: a buffer it delivers meanwhile is still recorded.
            if !keepOpen { input.stop() }
            let samples = state.withLock { state -> [Float] in
                // Move the samples out so the audio is released once the caller drops the clip.
                let samples = state.recording?.samples ?? []
                if let timings = state.recording?.timings { state.lastTimings = timings }
                state.recording = nil
                state.level = 0
                if !keepOpen {
                    state.inputOpen = false
                    state.preRoll.removeAll()
                }
                return samples
            }
            if keepOpen { reopenLater() }
            return AudioClip(samples: samples)
        }
    }

    /// Stops and drops the recording. A warm input stays open.
    public func cancel() {
        control.sync { dropRecording() }
    }

    /// Like `cancel`, but returns at once, so the caller never waits for a start still running in the background.
    /// The drop runs on the control queue after that start and before any call made after this one.
    public func cancelInBackground() {
        control.async { [self] in dropRecording() }
    }

    /// Keeps the input open after recordings and holds the last `preRoll` of audio for the next `start`. Opens the
    /// input now if it is closed; throws (and stays cold) if that fails.
    public func warmUp(preRoll: Duration) throws {
        try control.sync {
            let open = state.withLock { state -> Bool in
                state.warm = true
                let buffer = PreRoll(duration: preRoll)
                if buffer.capacity != state.preRoll.capacity { state.preRoll = buffer }
                return state.inputOpen
            }
            guard !open else { return }
            let generation = state.withLock { state in
                state.generation += 1
                state.inputOpen = true
                state.reopen = false
                return state.generation
            }
            do {
                try startInput(generation: generation)
            } catch {
                state.withLock { state in
                    state.warm = false
                    state.inputOpen = false
                }
                throw error
            }
        }
    }

    /// Leaves warm mode: closes the input now, or when the running recording ends. Drops the pre-roll.
    public func release() {
        control.sync {
            let close = state.withLock { state -> Bool in
                state.warm = false
                // `reopen` stays: a recording that is warm again by its end must still move to the new device.
                state.preRoll.removeAll()
                return state.recording == nil && state.inputOpen
            }
            if close { closeInput() }
        }
    }

    /// The input changed: the system default, the device list or the chosen device. An idle warm input moves to the
    /// new device at once (and one that could not open after a lost device tries again); during a recording the input
    /// stays on its device (a restart never switches devices) and moves when the recording ends, if it is warm by then.
    public func inputChanged() {
        control.async { [self] in
            let reopenNow = state.withLock { state -> Bool in
                // Marked even when cold: a finished dictation may warm the input up before `stop`.
                guard state.recording == nil else {
                    state.reopen = true
                    return false
                }
                return state.warm
            }
            if reopenNow { reopen() }
        }
    }

    /// Whether the input stays open between recordings.
    public var isWarm: Bool { state.withLock { $0.warm } }

    /// Level of the latest chunk for the meter, 0...1; zero outside a recording.
    public var level: Float { state.withLock { $0.level } }

    public var timings: Timings { state.withLock { $0.recording?.timings ?? $0.lastTimings } }

    /// Whether the input runs; for tests.
    var isInputOpen: Bool { state.withLock { $0.inputOpen } }

    /// Waits until everything queued on the control queue ran, such as a start in the background.
    func waitForControl() {
        control.sync {}
    }

    /// Call on `control` only. The body of `start`.
    private func startRecording(
        at startedAt: ContinuousClock.Instant, onInterruption: @escaping @Sendable () -> Void,
        signposts: Signposts? = nil
    ) throws {
        if state.withLock({ Self.startWarm(&$0, at: startedAt, onInterruption: onInterruption) }) { return }
        // Warm, but the input has to move to another device first; no recording is running yet.
        if state.withLock({ $0.warm && $0.inputOpen }) { input.stop() }
        // One lock for reset and first generation, so no callback can slip in between.
        let generation = state.withLock { state in
            state.generation += 1
            state.recording = Recording(
                startedAt: startedAt, onInterruption: onInterruption, firstGeneration: state.generation)
            state.level = 0
            state.lastTimings = Timings()
            // Open before the input starts: a chunk delivered inside `start` still counts.
            state.inputOpen = true
            state.reopen = false
            state.preRoll.removeAll()
            return state.generation
        }
        do {
            if let signposts {
                try signposts.measureMicrophoneStart { try startInput(generation: generation) }
            } else {
                try startInput(generation: generation)
            }
        } catch {
            state.withLock { state in
                state.recording = nil
                state.inputOpen = false
            }
            throw error
        }
    }

    /// Starts a recording on the running warm input, with the pre-roll as its beginning. False if not warm.
    private static func startWarm(
        _ state: inout State, at startedAt: ContinuousClock.Instant, onInterruption: @escaping @Sendable () -> Void
    ) -> Bool {
        guard state.warm, state.inputOpen, !state.reopen else { return false }
        let preRoll = state.preRoll.samples
        var recording = Recording(
            samples: preRoll, startedAt: startedAt, onInterruption: onInterruption,
            firstGeneration: state.generation)
        recording.timings.warm = true
        if !preRoll.isEmpty {
            let sound = !EngineLimits.isSilent(AudioClip(samples: preRoll))
            recording.timings = Timings(
                firstChunk: .zero, firstSound: sound ? .zero : nil, preRoll: state.preRoll.duration, warm: true)
        }
        state.preRoll.removeAll()
        state.recording = recording
        state.level = 0
        return true
    }

    /// Call on `control` only.
    private func startInput(generation: Int, restart: Bool = false) throws {
        let onChunk: @Sendable ([Float]) -> Void = { [weak self] in self?.append($0, generation: generation) }
        let onEvent: @Sendable (AudioInputEvent) -> Void = { [weak self] event in
            guard let self else { return }
            // Not on the caller's thread: a restart calls back into the input.
            control.async { self.handle(event, generation: generation) }
        }
        if restart {
            try input.restart(onChunk: onChunk, onEvent: onEvent)
        } else {
            try input.start(onChunk: onChunk, onEvent: onEvent)
        }
    }

    /// Call on `control` only. The body of `cancel`.
    private func dropRecording() {
        let keepOpen = state.withLock { state -> Bool in
            state.recording = nil
            state.level = 0
            state.lastTimings = Timings()
            return state.warm && state.inputOpen
        }
        if keepOpen { reopenLater() } else { closeInput() }
    }

    /// Call on `control` only.
    private func closeInput() {
        input.stop()
        state.withLock { state in
            state.inputOpen = false
            state.preRoll.removeAll()
        }
    }

    /// Call on `control` only. Opens the idle warm input again, on the device the input asks for now.
    private func reopen() {
        input.stop()
        let generation = state.withLock { state in
            state.generation += 1
            state.inputOpen = true
            state.reopen = false
            state.preRoll.removeAll()
            return state.generation
        }
        // On failure the input stays closed; the next `start` opens it cold.
        do {
            try startInput(generation: generation)
        } catch {
            state.withLock { $0.inputOpen = false }
        }
    }

    /// Call on `control` only. Queues the reopen behind the running call: the caller of `stop` or `cancel` must not
    /// wait for the engine to start before it goes on. The next `start` queues behind it.
    private func reopenLater() {
        control.async { [self] in
            if state.withLock({ $0.reopen }) { reopen() }
        }
    }

    /// Runs on `control`. Events of an older start are dropped. During a recording a format change restarts the
    /// same device and a lost device ends the recording; an idle warm input simply opens again.
    private func handle(_ event: AudioInputEvent, generation: Int) {
        enum Action {
            case ignore
            case restartRecording(@Sendable () -> Void)
            case interrupt(@Sendable () -> Void)
            case reopenIdle
        }
        let action = state.withLock { state -> Action in
            guard state.generation == generation else { return .ignore }
            if let interruption = state.recording?.onInterruption {
                guard event == .formatChanged else {
                    state.reopen = true
                    return .interrupt(interruption)
                }
                return .restartRecording(interruption)
            }
            return state.warm && state.inputOpen ? .reopenIdle : .ignore
        }
        switch action {
        case .ignore:
            return
        case .interrupt(let interruption):
            interruption()
        case .restartRecording(let interruption):
            let generation = state.withLock { state in
                state.generation += 1
                return state.generation
            }
            do {
                try startInput(generation: generation, restart: true)
            } catch {
                state.withLock { $0.reopen = true }
                interruption()
            }
        case .reopenIdle:
            reopen()
        }
    }

    private func append(_ chunk: [Float], generation: Int) {
        let arrival = now()
        let level = Self.meterLevel(rms: Self.rms(chunk))
        let silent = EngineLimits.isSilent(AudioClip(samples: chunk))
        state.withLock { state in
            // Fields are read one by one and samples are appended in place, so the buffer is never copied.
            guard state.recording != nil else {
                if state.warm, state.inputOpen, generation == state.generation { state.preRoll.append(chunk) }
                return
            }
            guard let firstGeneration = state.recording?.firstGeneration, generation >= firstGeneration,
                let startedAt = state.recording?.startedAt
            else { return }
            state.recording?.samples.append(contentsOf: chunk)
            state.level = level
            let elapsed = startedAt.duration(to: arrival)
            if state.recording?.timings.firstChunk == nil { state.recording?.timings.firstChunk = elapsed }
            if state.recording?.timings.firstSound == nil, !silent { state.recording?.timings.firstSound = elapsed }
        }
    }

    static func rms(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)).squareRoot()
    }

    /// RMS on a -50...0 dBFS scale, so normal speech fills about half of the meter.
    static func meterLevel(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        return min(max((20 * log10(rms) + 50) / 50, 0), 1)
    }
}
