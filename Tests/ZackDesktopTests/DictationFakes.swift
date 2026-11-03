import Foundation
import Synchronization
import Testing
import ZackCore

@testable import ZackDesktop

/// No-op defaults for the engine fakes; the production engines implement these themselves.
extension Transcriber {
    func prepare() async throws {}
}

extension Cleaner {
    func prepare() async throws {}
    func prewarm(mode: TextMode, vocabulary: [String], language: DictationLanguage) {}
    func discardPrewarmed() {}
}

/// `Clock` whose time moves only through `advance`; sleepers wake when their deadline passes.
final class TestClock: Clock, Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant { Instant(offset: offset + duration) }
        func duration(to other: Instant) -> Duration { other.offset - offset }
        static func < (lhs: Instant, rhs: Instant) -> Bool { lhs.offset < rhs.offset }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [UUID: Sleeper] = [:]
    }

    private let state = Mutex(State())

    var now: Instant { state.withLock { $0.now } }
    var minimumResolution: Duration { .zero }
    var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    func sleep(until deadline: Instant, tolerance: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                enum Outcome { case wait, resume, cancel }
                let outcome = state.withLock { state -> Outcome in
                    if Task.isCancelled { return .cancel }
                    if deadline <= state.now { return .resume }
                    state.sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return .wait
                }
                switch outcome {
                case .wait: break
                case .resume: continuation.resume()
                case .cancel: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            state.withLock { $0.sleepers.removeValue(forKey: id) }?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) {
        let due = state.withLock { state -> [Sleeper] in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let ids = state.sleepers.filter { $0.value.deadline <= now }.map(\.key)
            return ids.compactMap { state.sleepers.removeValue(forKey: $0) }
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}

actor FakeTranscriber: Transcriber {
    nonisolated let id = "fake"
    private var result: Result<String, ZackError>
    private(set) var calls = 0
    private(set) var lastHints: [String] = []
    private(set) var lastAudio: AudioClip?
    private var holdsNext = false
    private var held: CheckedContinuation<Void, Never>?

    init(_ text: String) {
        result = .success(text)
    }

    func respond(with result: Result<String, ZackError>) {
        self.result = result
    }

    /// The next transcription waits for `resume()`, as a slow engine would.
    func holdNext() {
        holdsNext = true
    }

    var isHeld: Bool { held != nil }

    /// Lets the held transcription go; one that has not started yet does not wait at all.
    func resume() {
        holdsNext = false
        held?.resume()
        held = nil
    }

    func transcribe(_ audio: AudioClip, hints: [String]) async throws -> String {
        calls += 1
        lastHints = hints
        lastAudio = audio
        if holdsNext {
            holdsNext = false
            await withCheckedContinuation { held = $0 }
        }
        return try result.get()
    }
}

/// Answers calls in order from `results`. The first call answers at once (a dictation that fails and leaves its audio
/// for "Erneut versuchen"); every later one waits until the test releases it. Unlike `FakeTranscriber`, several calls
/// can wait at once, as when a retry runs beside an aborted recognition.
actor QueuedTranscriber: Transcriber {
    nonisolated let id = "queued"
    private let results: [Result<String, ZackError>]
    private var calls = 0
    private var waiting: [Int: CheckedContinuation<Void, Never>] = [:]

    init(_ results: [Result<String, ZackError>]) {
        self.results = results
    }

    /// Calls waiting for `release`.
    var held: Int { waiting.count }

    /// Lets call `index` (0 is the first) return; it must be waiting already.
    func release(call index: Int) {
        waiting.removeValue(forKey: index)?.resume()
    }

    func transcribe(_ audio: AudioClip, hints: [String]) async throws -> String {
        let index = calls
        calls += 1
        if index > 0 { await withCheckedContinuation { waiting[index] = $0 } }
        return try results[index].get()
    }
}

/// Stands in for Apple's language model.
struct StubCleaner: Cleaner {
    let id = "stub"
    let output: String

    func clean(_ text: String, mode: TextMode, vocabulary: [String], language: DictationLanguage) async throws -> String
    { output }
}

/// A cleaner that does not answer: `clean` sleeps 30 s and ends early only when cancelled.
struct HangingCleaner: Cleaner {
    let id = "hanging"

    func clean(_ text: String, mode: TextMode, vocabulary: [String], language: DictationLanguage) async throws -> String
    {
        try await Task.sleep(for: .seconds(30))
        return text
    }
}

/// A cleaner that answers only once the test calls `release()`, well within the cleaner's limit of 2 s.
final class GatedCleaner: Cleaner {
    let id = "gated"
    let output: String
    private let waiting = Mutex<CheckedContinuation<Void, Never>?>(nil)

    init(output: String = "Das Treffen ist am Mittwoch.") {
        self.output = output
    }

    /// A cleanup waits for `release()`.
    var isWaiting: Bool { waiting.withLock { $0 != nil } }

    func release() {
        waiting.withLock { waiting -> CheckedContinuation<Void, Never>? in
            defer { waiting = nil }
            return waiting
        }?.resume()
    }

    func clean(_ text: String, mode: TextMode, vocabulary: [String], language: DictationLanguage) async throws -> String
    {
        await withCheckedContinuation { continuation in waiting.withLock { $0 = continuation } }
        return output
    }
}

/// Records what the controller asks of the cleaner. A class: the controller holds copies of the cleaner.
final class RecordingCleaner: Cleaner {
    struct Prewarm: Equatable {
        let mode: TextMode
        let vocabulary: [String]
    }

    private struct State {
        var prewarms: [Prewarm] = []
        var prewarmLanguages: [DictationLanguage] = []
        var cleanLanguages: [DictationLanguage] = []
        var discards = 0
        var cleans = 0
    }

    let id = "recording"
    let output: String
    private let state = Mutex(State())

    init(output: String = "Das Treffen ist am Mittwoch.") {
        self.output = output
    }

    var prewarms: [Prewarm] { state.withLock { $0.prewarms } }
    var prewarmLanguages: [DictationLanguage] { state.withLock { $0.prewarmLanguages } }
    var cleanLanguages: [DictationLanguage] { state.withLock { $0.cleanLanguages } }
    var discards: Int { state.withLock { $0.discards } }
    var cleans: Int { state.withLock { $0.cleans } }

    func clean(_ text: String, mode: TextMode, vocabulary: [String], language: DictationLanguage) async throws -> String
    {
        state.withLock {
            $0.cleans += 1
            $0.cleanLanguages.append(language)
        }
        return output
    }

    func prewarm(mode: TextMode, vocabulary: [String], language: DictationLanguage) {
        state.withLock {
            $0.prewarms.append(Prewarm(mode: mode, vocabulary: vocabulary))
            $0.prewarmLanguages.append(language)
        }
    }

    func discardPrewarmed() {
        state.withLock { $0.discards += 1 }
    }
}

/// Holds `makeProcessor` until the test lets it through.
actor ProcessorGate {
    private var open = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if open { return }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        open = true
        for continuation in waiting { continuation.resume() }
        waiting = []
    }
}

struct FakeTranscriberTests {
    /// A test may let go before the controller reached the transcription; it must not wait forever then.
    @Test func resumeBeforeTheHeldTranscriptionLetsItThrough() async {
        let transcriber = FakeTranscriber("Hallo")
        await transcriber.holdNext()
        await transcriber.resume()
        let text = TestValue<String?>(nil)
        Task { text.set(try? await transcriber.transcribe(AudioClip(samples: tone()), hints: [])) }
        #expect(await eventually(within: .milliseconds(500)) { text.current == "Hallo" })
    }

    @Test func resumeLetsTheHeldTranscriptionGo() async {
        let transcriber = FakeTranscriber("Hallo")
        await transcriber.holdNext()
        let text = TestValue<String?>(nil)
        Task { text.set(try? await transcriber.transcribe(AudioClip(samples: tone()), hints: [])) }
        #expect(await eventually { await transcriber.isHeld })
        #expect(text.current == nil)
        await transcriber.resume()
        #expect(await eventually { text.current == "Hallo" })
    }
}
