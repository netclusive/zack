import ZackCore

/// A second opinion that records its calls; it answers, fails, hangs until cancelled or waits for `release`.
public actor RecordingSecondOpinion: SecondOpinion {
    public enum Behavior: Sendable {
        case answer(String)
        case fail
        /// Sleeps until the caller cancels it.
        case hang
        /// Waits for `release()`, then answers; ignores cancellation like an engine that cannot stop mid-decode.
        case held(String)
    }

    public struct Call: Sendable, Equatable {
        public let samples: Int
        public let terms: [String]
        public let focus: [String]
        public let language: DictationLanguage
    }

    public struct Failure: Error {}

    public nonisolated let id = "recording"
    public private(set) var calls: [Call] = []
    private var behavior: Behavior
    private var callWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    public init(_ behavior: Behavior) {
        self.behavior = behavior
    }

    public func recognize(_ audio: AudioClip, terms: [String], focus: [String], language: DictationLanguage)
        async throws -> String
    {
        calls.append(Call(samples: audio.samples.count, terms: terms, focus: focus, language: language))
        for waiter in callWaiters { waiter.resume() }
        callWaiters = []
        switch behavior {
        case .answer(let text): return text
        case .fail: throw Failure()
        case .hang:
            try await Task.sleep(for: .seconds(3600))
            throw CancellationError()
        case .held(let text):
            if !released { await withCheckedContinuation { releaseWaiters.append($0) } }
            return text
        }
    }

    /// Returns once `recognize` has been called at least once.
    public func waitForCall() async {
        guard calls.isEmpty else { return }
        await withCheckedContinuation { callWaiters.append($0) }
    }

    /// Lets held calls answer.
    public func release() {
        released = true
        for waiter in releaseWaiters { waiter.resume() }
        releaseWaiters = []
    }
}
