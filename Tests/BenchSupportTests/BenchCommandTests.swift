import Testing
import ZackCore

@testable import BenchSupport

private struct FakeCleaner: Cleaner {
    let id: String
    func clean(_ text: String, mode: TextMode, vocabulary: [String]) async throws -> String { text }
}

private let extras: [String: CleanerFactory] = [
    "fake-b": { FakeCleaner(id: "fake-b") }, "fake-a": { FakeCleaner(id: "fake-a") },
]

@Test func builtInCleanersComeFirstAndExtrasAreSorted() {
    #expect(Registry().cleanerIDs == ["none", "apple-fm"])
    #expect(Registry(extraCleaners: extras).cleanerIDs == ["none", "apple-fm", "fake-a", "fake-b"])
}

@Test func extraCleanerIsCreatedByItsFactory() throws {
    let registry = Registry(extraCleaners: extras)
    #expect(try registry.cleaner("fake-a")?.id == "fake-a")
    #expect(try registry.cleaner("none") == nil)
    #expect(try registry.cleaner("apple-fm")?.id == "apple-fm")
}

@Test func unknownCleanerListsExtras() {
    #expect(
        throws: ArgumentError.invalidValue(
            option: "--cleaner", value: "nope", allowed: ["none", "apple-fm", "fake-a", "fake-b"])
    ) {
        try Registry(extraCleaners: extras).cleaner("nope")
    }
}

/// The plain bench must keep its help text.
@Test func defaultUsageIsUnchanged() {
    let expected = """
        zack-bench <command> [options]

          synth   [--audio-dir bench/corpus/audio-synth] [--voice Anna] [--id <case>]
          record  [--audio-dir bench/corpus/audio] [--id <case>] [--all]
          mic-check [--repeat 5] [--device <Name>]
          run     --transcriber <id> [--cleaner none] [--repeat 5] [--audio-dir bench/corpus/audio]
                  [--results bench/results]
          report  [--results bench/results] [--all]

        transcribers: apple-speech, apple-dictation, parakeet-v3, parakeet-ultra
        cleaners:     none, apple-fm
        """
    #expect(BenchCommand.usage(name: "zack-bench", registry: Registry()) == expected)
}

@Test func whisperIsNoLongerATranscriber() {
    #expect(throws: ArgumentError.self) { try Registry.transcriber("whisper-turbo") }
}

@Test func runAcceptsRepeat() throws {
    let arguments = try Arguments(
        ["zack-bench", "run", "--transcriber", "parakeet-v3", "--repeat", "3"], spec: BenchCommand.spec)
    #expect(try arguments.positiveInteger("repeat", default: 5) == 3)
}

@Test func usageNamesTheToolAndListsExtraCleaners() {
    let usage = BenchCommand.usage(name: "zack-bench-x", registry: Registry(extraCleaners: extras))
    #expect(usage.hasPrefix("zack-bench-x <command> [options]"))
    #expect(usage.contains("cleaners:     none, apple-fm, fake-a, fake-b"))
}
