import Testing
import ZackApple
import ZackCore

@testable import BenchSupport

private struct FakeCleaner: Cleaner {
    let id: String
    func clean(_ text: String, mode: TextMode, vocabulary: [String], language: DictationLanguage) async throws -> String
    { text }
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

          synth   [--language de|en] [--audio-dir bench/corpus/audio-synth] [--voice Anna] [--id <case>]
          record  [--language de|en] [--audio-dir bench/corpus/audio] [--id <case>] [--all]
          mic-check [--repeat 5] [--device <Name>]
          run     --transcriber <id> [--language de|en] [--cleaner none] [--repeat 5]
                  [--audio-dir bench/corpus/audio] [--results bench/results]
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

private func defaults(_ extra: [String]) throws -> BenchDefaults {
    try BenchDefaults(arguments: Arguments(["zack-bench", "run"] + extra, spec: BenchCommand.spec))
}

@Test func withoutLanguageTheGermanDefaultsApply() throws {
    let german = try defaults([])
    #expect(german.language == .german)
    #expect(german.corpus == "bench/corpus/cases.json")
    #expect(german.voice == "Anna")
    #expect(german.synthDirectory == "bench/corpus/audio-synth")
    #expect(german.audioDirectory == "bench/corpus/audio")
    #expect(try defaults(["--language", "de"]) == german)
}

@Test func englishLanguageSwitchesTheDefaults() throws {
    let english = try defaults(["--language", "en"])
    #expect(english.language == .english)
    #expect(english.corpus == "bench/corpus/cases-en.json")
    #expect(english.voice == "Samantha")
    #expect(english.synthDirectory == "bench/corpus/audio-synth-en")
    #expect(english.audioDirectory == "bench/corpus/audio-en")
}

@Test func explicitOptionsBeatTheLanguageDefaults() throws {
    let arguments = try Arguments(
        ["zack-bench", "run", "--language", "en", "--corpus", "x.json"], spec: BenchCommand.spec)
    #expect(arguments["corpus"] == "x.json")
    #expect(try BenchDefaults(arguments: arguments).language == .english)
}

@Test func unknownLanguageIsRejected() {
    #expect(throws: ArgumentError.invalidValue(option: "--language", value: "fr", allowed: ["de", "en"])) {
        try defaults(["--language", "fr"])
    }
}

@Test func appleTranscriberFollowsTheLanguage() throws {
    let english = try #require(try Registry.transcriber("apple-speech", language: .english) as? AppleTranscriber)
    #expect(english.locale.identifier == "en-US")
    let german = try #require(try Registry.transcriber("apple-speech", language: .german) as? AppleTranscriber)
    #expect(german.locale.identifier == "de-DE")
}
