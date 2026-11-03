import Foundation
import Testing
import ZackCore

@testable import BenchSupport

/// No-op default for the transcriber fakes; the production transcribers implement it themselves.
extension Transcriber {
    func prepare() async throws {}
}

/// Returns `text(call, sampleCount)` and records the sample count of every clip it gets, in call order.
private actor FakeTranscriber: Transcriber {
    nonisolated let id = "fake"
    private(set) var calls: [Int] = []
    private let text: @Sendable (Int, Int) -> String

    init(text: @escaping @Sendable (Int, Int) -> String) {
        self.text = text
    }

    func transcribe(_ audio: AudioClip, hints: [String]) async throws -> String {
        calls.append(audio.samples.count)
        return text(calls.count, audio.samples.count)
    }
}

private struct Failure: Error {}

/// Like `FakeTranscriber`, but throws on the listed calls.
private actor FailingTranscriber: Transcriber {
    nonisolated let id = "failing"
    private var count = 0
    private let failing: Set<Int>

    init(failing: Set<Int>) {
        self.failing = failing
    }

    func transcribe(_ audio: AudioClip, hints: [String]) async throws -> String {
        count += 1
        if failing.contains(count) { throw Failure() }
        return audio.samples.count == 1600 ? "eins zwei" : "drei vier"
    }
}

private final class Lines {
    var all: [String] = []
}

/// Two cases with clips of 1600 and 3200 samples; returns the corpus and the audio folder.
private func fixture() throws -> (Corpus, URL) {
    let json = """
        {"vocabulary":[],"snippets":[],"cases":[
         {"id":"a","group":"prose","mode":"prose","spoken":"eins zwei","expected":"eins zwei","terms":[]},
         {"id":"b","group":"long","mode":"prose","spoken":"drei vier","expected":"drei vier","terms":[]}]}
        """
    let directory = FileManager.default.temporaryDirectory.appending(path: "zack-runner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    for (id, count) in [("a", 1600), ("b", 3200)] {
        try WAVFile.encode(AudioClip(samples: Array(repeating: 0.1, count: count)))
            .write(to: directory.appending(path: "\(id).wav"))
    }
    return (try Corpus.decode(Data(json.utf8)), directory)
}

@Test func repeatedPassesRunRoundRobinAfterWarmUp() async throws {
    let (corpus, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transcriber = FakeTranscriber { _, count in count == 1600 ? "eins zwei" : "drei vier" }
    let runner = BenchRunner(
        corpus: corpus, transcriber: transcriber, cleaner: nil, audioDirectory: directory, repeats: 3,
        log: { _ in })
    let result = try await runner.run()
    // Warm-up first, then pass 1 over all cases, pass 2, pass 3.
    #expect(await transcriber.calls == [1600, 1600, 3200, 1600, 3200, 1600, 3200])
    for testCase in result.cases {
        #expect(testCase.transcribeSamples.count == 3, "\(testCase.id)")
        #expect(testCase.totalSamples.count == 3, "\(testCase.id)")
        #expect(testCase.transcribeSamplesMs?.first == testCase.transcribeMs)
    }
    #expect(result.cases.map(\.audioSeconds) == [0.1, 0.2])
    #expect(RunSummary(result).transcribeSamples == 6)
}

@Test func laterPassesAreKeptAndDifferencesFromPassOneAreLogged() async throws {
    let (corpus, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    // Call 1 is the warm-up, calls 2 and 3 are pass 1; case a differs in pass 2 (call 4).
    let transcriber = FakeTranscriber { call, count in
        call == 4 ? "eins drei" : count == 1600 ? "eins zwei" : "drei vier"
    }
    let lines = Lines()
    let runner = BenchRunner(
        corpus: corpus, transcriber: transcriber, cleaner: nil, audioDirectory: directory, repeats: 2,
        log: { lines.all.append($0) })
    let result = try await runner.run()
    let first = try #require(result.cases.first { $0.id == "a" })
    #expect(first.final == "eins zwei")
    #expect(first.wer == 0)
    #expect(first.transcribeSamples.count == 2)
    let warnings = lines.all.filter { $0.hasPrefix("warning:") }
    #expect(warnings.count == 1, "\(lines.all)")
    #expect(warnings.first?.contains("a") == true)
    #expect(warnings.first?.contains("pass 2") == true)
}

@Test func qualityIsAveragedOverAllPassesAndUnstableCasesAreCounted() async throws {
    let (corpus, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    // Call 1 is the warm-up; case a answers with nothing in pass 2 (call 4), like Whisper's fallback does.
    let transcriber = FakeTranscriber { call, count in
        call == 4 ? "" : count == 1600 ? "eins zwei" : "drei vier"
    }
    let runner = BenchRunner(
        corpus: corpus, transcriber: transcriber, cleaner: nil, audioDirectory: directory, repeats: 2,
        log: { _ in })
    let summary = RunSummary(try await runner.run())
    // Case a: WER 0 and 1 over two passes, case b: 0 in both.
    #expect(abs((summary.meanWER ?? -1) - 0.25) < 0.0001, "\(String(describing: summary.meanWER))")
    #expect(summary.unstableCases == 1)
}

@Test func deterministicTranscriberHasNoUnstableCases() async throws {
    let (corpus, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let transcriber = FakeTranscriber { _, count in count == 1600 ? "eins zwei" : "drei vier" }
    let runner = BenchRunner(
        corpus: corpus, transcriber: transcriber, cleaner: nil, audioDirectory: directory, repeats: 3,
        log: { _ in })
    let summary = RunSummary(try await runner.run())
    #expect(summary.meanWER == 0)
    #expect(summary.unstableCases == 0)
}

@Test func rawTextIsKeptPerPassAndFailedLaterPassesAreCounted() async throws {
    let (corpus, directory) = try fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    // Call 1 is the warm-up, calls 2 and 3 are pass 1; case a fails in pass 2 (call 4).
    let runner = BenchRunner(
        corpus: corpus, transcriber: FailingTranscriber(failing: [4]), cleaner: nil, audioDirectory: directory,
        repeats: 3, log: { _ in })
    let result = try await runner.run()
    let first = try #require(result.cases.first { $0.id == "a" })
    let second = try #require(result.cases.first { $0.id == "b" })
    #expect(first.rawPasses == ["eins zwei", "eins zwei"])
    #expect(first.failedLaterPasses == 1)
    #expect(second.rawPasses == ["drei vier", "drei vier", "drei vier"])
    #expect(second.failedLaterPasses == 0)
    let summary = RunSummary(result)
    #expect(summary.errorCount == 0)
    #expect(summary.failedLaterPasses == 1)
    #expect(BenchReport.markdown([summary]).contains("| 2 | 0 (+1) |"))
}

@Test func runnerAppliesItsLanguageToRulesAndWordErrorRate() async throws {
    let json = """
        {"vocabulary":[],"snippets":[],"cases":[
         {"id":"a","group":"prose","mode":"prose","spoken":"The build is green.","expected":"The build is green.","terms":[]}]}
        """
    let directory = FileManager.default.temporaryDirectory.appending(path: "zack-runner-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try WAVFile.encode(AudioClip(samples: Array(repeating: 0.1, count: 1600)))
        .write(to: directory.appending(path: "a.wav"))
    let corpus = try Corpus.decode(Data(json.utf8))
    func run(_ language: DictationLanguage) async throws -> CaseResult {
        let runner = BenchRunner(
            corpus: corpus, transcriber: FakeTranscriber { _, _ in "Um, the build is green." }, cleaner: nil,
            audioDirectory: directory, repeats: 1, language: language, log: { _ in })
        return try #require(try await runner.run().cases.first)
    }
    let english = try await run(.english)
    #expect(english.wer == 0)
    #expect(english.final == "The build is green.")
    let german = try await run(.german)
    #expect(german.wer > 0)
}
