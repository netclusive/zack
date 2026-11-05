import Dispatch
import Synchronization

@testable import ZackDesktop

/// Records the commands sent to the player, in order.
final class FakePlaybackCommands: PlaybackCommands {
    enum Call: Equatable { case pause, play }

    private let recorded = Mutex<[Call]>([])

    var calls: [Call] { recorded.withLock { $0 } }

    func pause() {
        recorded.withLock { $0.append(.pause) }
    }

    func play() {
        recorded.withLock { $0.append(.play) }
    }
}

/// Stands in for Core Audio: the test sets which bundle IDs output audio.
final class FakeAudioOutputs: AudioOutputs {
    private struct State {
        var playing: Set<String>
        var reads = 0
        /// Set by `holdNextRead`, taken by the next read.
        var gate: DispatchSemaphore?
        /// The gate a read is waiting on.
        var waiting: DispatchSemaphore?
    }

    private let state: Mutex<State>

    init(_ playing: Set<String>) {
        state = Mutex(State(playing: playing))
    }

    var playing: Set<String> {
        get { state.withLock { $0.playing } }
        set { state.withLock { $0.playing = newValue } }
    }

    var reads: Int { state.withLock { $0.reads } }

    /// The next read waits until `release()`, at most 2 s; a release before that read lets it through at once.
    func holdNextRead() {
        state.withLock { $0.gate = DispatchSemaphore(value: 0) }
    }

    func release() {
        state.withLock { state -> DispatchSemaphore? in
            defer {
                state.gate = nil
                state.waiting = nil
            }
            return state.waiting ?? state.gate
        }?.signal()
    }

    func playingBundleIDs() -> Set<String> {
        let gate = state.withLock { state -> DispatchSemaphore? in
            state.reads += 1
            state.waiting = state.gate
            state.gate = nil
            return state.waiting
        }
        _ = gate?.wait(timeout: .now() + 2)
        return playing
    }
}
