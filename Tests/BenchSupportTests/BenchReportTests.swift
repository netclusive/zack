import Foundation
import Testing

@testable import BenchSupport

private func sample(
    _ id: String, group: String, wer: Double, terms: Double?, match: Bool, cleaner: Bool, ms: Double,
    rejected: Bool = false
) -> CaseResult {
    CaseResult(
        id: id, group: group, raw: "", final: "", wer: wer, termHitRate: terms, matchesExpected: match,
        usedCleaner: cleaner, cleanerAttempted: cleaner || rejected, cleanerRejected: rejected,
        cleanerMs: cleaner || rejected ? 1 : 0, transcribeMs: ms, processMs: 1)
}

@Test func summaryAggregatesGroups() {
    let run = RunResult(
        date: Date(timeIntervalSince1970: 0), transcriber: "t", cleaner: "c", audioDir: "a", peakMemoryMB: 100,
        cases: [
            sample("d01", group: "dengl", wer: 0.1, terms: 1, match: true, cleaner: false, ms: 40),
            sample("d02", group: "dengl", wer: 0.3, terms: 0.5, match: false, cleaner: false, ms: 60),
            sample("c01", group: "correction", wer: 0, terms: 1, match: true, cleaner: true, ms: 50),
            sample("c02", group: "correction", wer: 0, terms: 1, match: false, cleaner: true, ms: 70),
        ])
    let summary = RunSummary(run)
    #expect(abs((summary.meanWER ?? -1) - 0.1) < 0.0001)
    #expect(summary.denglTermRate == 0.75)
    #expect(summary.correctionRate == 0.5)
    #expect(summary.p95TotalWithoutCleanerMs == 61)
    #expect(summary.p95TotalWithCleanerMs == 71)
}

@Test func markdownTableHasRowPerRun() {
    let run = RunResult(
        date: Date(), transcriber: "parakeet-v3", cleaner: "none", audioDir: "a", peakMemoryMB: 1, cases: [])
    let table = BenchReport.markdown([RunSummary(run)])
    #expect(table.contains("| parakeet-v3 | none | a |"))
    #expect(table.split(separator: "\n").count == 3)
}

@Test func resultRoundTripsThroughJSON() throws {
    let run = RunResult(
        date: Date(timeIntervalSince1970: 0), transcriber: "t", cleaner: "c", audioDir: "a", peakMemoryMB: 1,
        cases: [sample("d01", group: "dengl", wer: 0.1, terms: 1, match: true, cleaner: false, ms: 40)])
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(RunResult.self, from: encoder.encode(run))
    #expect(decoded.cases.first?.id == "d01")
    #expect(decoded.transcriber == "t")
}

@Test func rejectedCleanerCasesCountAsAttempted() {
    let run = RunResult(
        date: Date(timeIntervalSince1970: 0), transcriber: "t", cleaner: "c", audioDir: "a", peakMemoryMB: 1,
        cases: [
            sample("a", group: "prose", wer: 0, terms: 1, match: true, cleaner: false, ms: 10),
            sample("b", group: "prose", wer: 0, terms: 1, match: true, cleaner: true, ms: 20),
            sample("c", group: "prose", wer: 0, terms: 1, match: true, cleaner: false, ms: 500, rejected: true),
        ])
    let summary = RunSummary(run)
    #expect(summary.cleanerAttempts == 2)
    #expect(summary.cleanerRejectionRate == 0.5)
    #expect(summary.p95TotalWithoutCleanerMs == 11)
    #expect(summary.p95TotalWithCleanerMs == 501)
}

@Test func noCleanerAttemptsMeansNoRejectionRate() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
        cases: [sample("a", group: "prose", wer: 0, terms: 1, match: true, cleaner: false, ms: 10)])
    #expect(RunSummary(run).cleanerRejectionRate == nil)
}

@Test func failedCasesAreExcludedFromAggregates() {
    let failed = CaseResult(
        id: "x", group: "dengl", raw: "", final: "", wer: 1, termHitRate: nil, matchesExpected: false,
        usedCleaner: false, cleanerAttempted: false, cleanerRejected: false, cleanerMs: 0, transcribeMs: 1,
        processMs: 0, error: "boom")
    let run = RunResult(
        date: Date(timeIntervalSince1970: 0), transcriber: "t", cleaner: "c", audioDir: "a", peakMemoryMB: 1,
        cases: [sample("d01", group: "dengl", wer: 0.2, terms: 1, match: true, cleaner: false, ms: 40), failed])
    let summary = RunSummary(run)
    #expect(summary.errorCount == 1)
    #expect(abs((summary.meanWER ?? -1) - 0.2) < 0.0001)
    #expect(summary.denglTermRate == 1)
    #expect(summary.p50TranscribeMs == 40)
    #expect(BenchReport.markdown([summary]).contains("| Fehler |"))
}

@Test func memoryIsShownForInProcessEngines() {
    let run = RunResult(
        date: Date(), transcriber: "parakeet-v3", cleaner: "none", audioDir: "a", peakMemoryMB: 900,
        loadMemoryMB: 800, cases: [])
    let table = BenchReport.markdown([RunSummary(run)])
    #expect(table.contains("| 800 | 900 |"))
    #expect(table.contains("Speicher Laden MB"))
}

@Test func memoryIsNotComparableForAppleSpeech() {
    for id in ["apple-speech", "apple-dictation"] {
        let run = RunResult(
            date: Date(), transcriber: id, cleaner: "none", audioDir: "a", peakMemoryMB: 90, loadMemoryMB: 80,
            cases: [])
        let table = BenchReport.markdown([RunSummary(run)])
        #expect(table.contains("| n/a | n/a |"))
        #expect(!table.contains("| 80 |"))
    }
}

@Test func latestRunPerCombinationWins() {
    func run(_ transcriber: String, _ cleaner: String, at seconds: Double, wer: Double) -> RunResult {
        RunResult(
            date: Date(timeIntervalSince1970: seconds), transcriber: transcriber, cleaner: cleaner, audioDir: "a",
            peakMemoryMB: 1,
            cases: [sample("a", group: "prose", wer: wer, terms: 1, match: true, cleaner: false, ms: 1)])
    }
    let latest = BenchReport.latest([
        run("t", "none", at: 10, wer: 0.5), run("t", "none", at: 20, wer: 0.1), run("t", "apple-fm", at: 5, wer: 0.2),
    ])
    #expect(latest.count == 2)
    #expect(latest.first { $0.cleaner == "none" }?.cases.first?.wer == 0.1)
}

@Test func latestKeepsSyntheticAndRecordedRunsApart() {
    func run(_ audioDir: String, at seconds: Double) -> RunResult {
        RunResult(
            date: Date(timeIntervalSince1970: seconds), transcriber: "t", cleaner: "none", audioDir: audioDir,
            peakMemoryMB: 1, cases: [])
    }
    let latest = BenchReport.latest([run("audio", at: 10), run("audio-synth", at: 20), run("audio", at: 5)])
    #expect(latest.count == 2)
    #expect(Set(latest.map(\.audioDir)) == ["audio", "audio-synth"])
}

@Test func rowsAreGroupedByAudioDirectory() {
    func summary(_ audioDir: String, terms: Double) -> RunSummary {
        RunSummary(
            RunResult(
                date: Date(), transcriber: "t-\(audioDir)", cleaner: "none", audioDir: audioDir, peakMemoryMB: 1,
                cases: [sample("a", group: "prose", wer: 0, terms: terms, match: true, cleaner: false, ms: 1)]))
    }
    let table = BenchReport.markdown([
        summary("audio-synth", terms: 1), summary("audio", terms: 0.5), summary("audio-synth", terms: 0.2),
    ])
    let rows = table.split(separator: "\n").dropFirst(2).map {
        $0.split(separator: "|")[2].trimmingCharacters(in: .whitespaces)
    }
    #expect(rows == ["audio", "audio-synth", "audio-synth"])
    #expect(table.contains("| Erkennung | Glättung | Audio | WER |"))
}

@Test func termRateIgnoresCasesWithoutTerms() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
        cases: [
            sample("p01", group: "prose", wer: 0, terms: nil, match: true, cleaner: false, ms: 1),
            sample("p02", group: "prose", wer: 0, terms: nil, match: true, cleaner: false, ms: 1),
            sample("d01", group: "dengl", wer: 0, terms: 0.5, match: true, cleaner: false, ms: 1),
            sample("v01", group: "vocabulary", wer: 0, terms: 1, match: true, cleaner: false, ms: 1),
        ])
    let summary = RunSummary(run)
    #expect(summary.termRate == 0.75)
    #expect(summary.denglTermRate == 0.5)
}

@Test func termRateIsNilWhenNoCaseHasTerms() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
        cases: [sample("p01", group: "prose", wer: 0, terms: nil, match: true, cleaner: false, ms: 1)])
    #expect(RunSummary(run).termRate == nil)
}

@Test func legacyResultJSONWithStoredTermRateStillDecodes() throws {
    let json = """
        {"id":"p01","group":"prose","raw":"","final":"","wer":0,"termHitRate":1,"matchesExpected":true,
         "usedCleaner":false,"cleanerAttempted":false,"cleanerRejected":false,"cleanerMs":0,
         "transcribeMs":1,"processMs":1}
        """
    let decoded = try JSONDecoder().decode(CaseResult.self, from: Data(json.utf8))
    #expect(decoded.termHitRate == 1)
}

@Test func tenSecondLatencyUsesLongCasesWithoutCleaner() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
        cases: [
            sample("p01", group: "prose", wer: 0, terms: nil, match: true, cleaner: false, ms: 500),
            sample("l01", group: "long", wer: 0, terms: nil, match: true, cleaner: false, ms: 100),
            sample("l02", group: "long", wer: 0, terms: nil, match: true, cleaner: false, ms: 150),
            sample("l03", group: "long", wer: 0, terms: nil, match: true, cleaner: true, ms: 900),
        ])
    let summary = RunSummary(run)
    #expect(summary.p95LongWithoutCleanerMs == 151)
    #expect(
        BenchReport.markdown([summary]).contains(
            "| p95 ohne KI ms | p95 10 s ohne KI ms | Ø lang s | p95 mit KI ms |"))
}

@Test func tenSecondLatencyShowsDashWithoutLongCases() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
        cases: [sample("p01", group: "prose", wer: 0, terms: nil, match: true, cleaner: false, ms: 10)])
    #expect(RunSummary(run).p95LongWithoutCleanerMs == nil)
}

@Test func missingValuesShowDash() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
        cases: [sample("a", group: "prose", wer: 0, terms: 1, match: true, cleaner: false, ms: 10)])
    let summary = RunSummary(run)
    #expect(summary.denglTermRate == nil)
    #expect(summary.correctionRate == nil)
    #expect(summary.p95TotalWithCleanerMs == nil)
    let row = BenchReport.markdown([summary]).split(separator: "\n").last ?? ""
    #expect(row.contains("| - | - | 10 (n=1) | 10 (n=1) | 11 (n=1) | - | - | - | - |"))
}

@Test func footnoteExplainsWER() {
    #expect(BenchReport.footnote.contains("WER"))
    #expect(BenchReport.footnote.contains("nur Fälle mit Begriffen"))
    #expect(BenchReport.footnote.contains("long"))
}

@Test func footnoteExplainsSampleCounts() {
    #expect(BenchReport.footnote.contains("--repeat"))
    #expect(BenchReport.footnote.contains("n = Anzahl der Messungen"))
    #expect(BenchReport.footnote.contains("über alle Durchläufe gemittelt"))
}

/// With one sample per case, nearest-rank p95 over a handful of cases is just the slowest one.
@Test func latencyPercentilesUseEverySample() {
    let long = CaseResult(
        id: "l01", group: "long", raw: "", final: "", wer: 0, termHitRate: nil, matchesExpected: true,
        usedCleaner: false, cleanerAttempted: false, cleanerRejected: false, cleanerMs: 0, transcribeMs: 10,
        processMs: 1, transcribeSamplesMs: [10, 40, 20, 30], processSamplesMs: [1, 1, 1, 1])
    let cleaned = CaseResult(
        id: "c01", group: "correction", raw: "", final: "", wer: 0, termHitRate: nil, matchesExpected: true,
        usedCleaner: true, cleanerAttempted: true, cleanerRejected: false, cleanerMs: 300, transcribeMs: 10,
        processMs: 300, transcribeSamplesMs: [10, 10], processSamplesMs: [300, 500])
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "c", audioDir: "a", peakMemoryMB: 1, cases: [long, cleaned])
    let summary = RunSummary(run)
    #expect(summary.p50TranscribeMs == 10)
    #expect(summary.p95TranscribeMs == 40)
    #expect(summary.transcribeSamples == 6)
    #expect(summary.p95TotalWithoutCleanerMs == 41)
    #expect(summary.withoutCleanerSamples == 4)
    #expect(summary.p95LongWithoutCleanerMs == 41)
    #expect(summary.longWithoutCleanerSamples == 4)
    #expect(summary.p95TotalWithCleanerMs == 510)
    #expect(summary.withCleanerSamples == 2)
    let row = BenchReport.markdown([summary]).split(separator: "\n").last ?? ""
    #expect(row.contains("| 10 (n=6) | 40 (n=6) | 41 (n=4) | 41 (n=4) | - | 510 (n=2) |"), "\(row)")
}

@Test func legacyCaseJSONWithoutSamplesUsesItsSingleTiming() throws {
    let json = """
        {"id":"p01","group":"prose","raw":"","final":"","wer":0,"matchesExpected":true,
         "usedCleaner":false,"cleanerAttempted":false,"cleanerRejected":false,"cleanerMs":0,
         "transcribeMs":7,"processMs":2}
        """
    let decoded = try JSONDecoder().decode(CaseResult.self, from: Data(json.utf8))
    #expect(decoded.transcribeSamplesMs == nil)
    #expect(decoded.transcribeSamples == [7])
    #expect(decoded.totalSamples == [9])
}

@Test func allFailedRunShowsDashesNotPerfectScores() {
    let failed = CaseResult(
        id: "x", group: "dengl", raw: "", final: "", wer: 1, termHitRate: nil, matchesExpected: false,
        usedCleaner: false, cleanerAttempted: false, cleanerRejected: false, cleanerMs: 0, transcribeMs: 1,
        processMs: 0, error: "boom")
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1, cases: [failed])
    let summary = RunSummary(run)
    #expect(summary.meanWER == nil)
    #expect(summary.termRate == nil)
    #expect(summary.p50TranscribeMs == nil)
    #expect(summary.p95TranscribeMs == nil)
    let row = String(BenchReport.markdown([summary]).split(separator: "\n").last ?? "")
    #expect(row.hasPrefix("| t | none | a | - | - | - | - | - | - | - | - | - | - | - | - | 0 | 1 |"))
}

@Test func reportListsDistinctOSBuildsBelowTable() {
    func run(_ transcriber: String, os: String?) -> RunSummary {
        RunSummary(
            RunResult(
                date: Date(), transcriber: transcriber, cleaner: "none", audioDir: "a", peakMemoryMB: 1,
                osBuild: os, cases: []))
    }
    let markdown = BenchReport.markdown([
        run("t1", os: "Version 27.0 (Build 27A1)"), run("t2", os: "Version 27.0 (Build 27A1)"),
        run("t3", os: "Version 27.1 (Build 27B2)"), run("t4", os: nil),
    ])
    #expect(markdown.hasSuffix("\n\nmacOS: Version 27.0 (Build 27A1), Version 27.1 (Build 27B2)"))
}

@Test func reportOmitsOSLineWhenNoBuildIsKnown() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1, cases: [])
    #expect(!BenchReport.markdown([RunSummary(run)]).contains("macOS"))
}

@Test func legacyRunJSONWithoutOSBuildStillDecodes() throws {
    let json = """
        {"date":"1970-01-01T00:00:00Z","transcriber":"t","cleaner":"c","audioDir":"a","peakMemoryMB":1,
         "loadMemoryMB":0,"cases":[]}
        """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    #expect(try decoder.decode(RunResult.self, from: Data(json.utf8)).osBuild == nil)
}

@Test func caseCountShowsCasesWithoutErrors() {
    let failed = CaseResult(
        id: "x", group: "dengl", raw: "", final: "", wer: 1, termHitRate: nil, matchesExpected: false,
        usedCleaner: false, cleanerAttempted: false, cleanerRejected: false, cleanerMs: 0, transcribeMs: 1,
        processMs: 0, error: "boom")
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
        cases: [
            sample("p01", group: "prose", wer: 0, terms: nil, match: true, cleaner: false, ms: 1),
            sample("p02", group: "prose", wer: 0, terms: nil, match: true, cleaner: false, ms: 1), failed,
        ])
    let summary = RunSummary(run)
    #expect(summary.caseCount == 2)
    let table = BenchReport.markdown([summary])
    #expect(table.contains("| KI verworfen | instabil | Fälle | Fehler |"))
    #expect(table.split(separator: "\n").last?.contains("| - | - | 2 | 1 |") == true, "\(table)")
}

/// The 10 s latency target only holds if the long recordings are about 10 s long.
@Test func meanLongClipDurationIsShownPerRun() {
    func timed(_ id: String, group: String, seconds: Double?, error: String? = nil) -> CaseResult {
        CaseResult(
            id: id, group: group, raw: "", final: "", wer: 0, termHitRate: nil, matchesExpected: true,
            usedCleaner: false, cleanerAttempted: false, cleanerRejected: false, cleanerMs: 0, transcribeMs: 1,
            processMs: 1, error: error, audioSeconds: seconds)
    }
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
        cases: [
            timed("p01", group: "prose", seconds: 2), timed("l01", group: "long", seconds: 9.5),
            timed("l02", group: "long", seconds: 10.75), timed("l03", group: "long", seconds: 30, error: "boom"),
        ])
    let summary = RunSummary(run)
    #expect(summary.meanLongSeconds == 10.125)
    let row = BenchReport.markdown([summary]).split(separator: "\n").last ?? ""
    #expect(row.contains("| 2 (n=2) | 10.1 | - |"), "\(row)")
}

@Test func meanLongClipDurationIsUnknownInOldRuns() throws {
    let json = """
        {"id":"l01","group":"long","raw":"","final":"","wer":0,"matchesExpected":true,
         "usedCleaner":false,"cleanerAttempted":false,"cleanerRejected":false,"cleanerMs":0,
         "transcribeMs":1,"processMs":1}
        """
    let decoded = try JSONDecoder().decode(CaseResult.self, from: Data(json.utf8))
    #expect(decoded.audioSeconds == nil)
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1, cases: [decoded])
    #expect(RunSummary(run).meanLongSeconds == nil)
}

@Test func footnoteExplainsCaseCountAndClipLength() {
    #expect(BenchReport.footnote.contains("Fälle"))
    #expect(BenchReport.footnote.contains("Ø lang s"))
}

/// Memory columns measure this process only; Apple's models run elsewhere. The bench has no MLX engine any more.
@Test func footnoteNamesWhatMemoryLeavesOut() {
    #expect(BenchReport.footnote.contains("apple-fm"))
    #expect(BenchReport.footnote.contains("außerhalb des Prozesses"))
    #expect(!BenchReport.footnote.contains("MLX"))
}

private func passed(
    _ id: String, group: String, wer: [Double], terms: [Double] = [], match: [Bool], attempted: [Bool],
    rejected: [Bool], finals: [String]
) -> CaseResult {
    CaseResult(
        id: id, group: group, raw: "", final: finals[0], wer: wer[0], termHitRate: terms.first,
        matchesExpected: match[0], usedCleaner: false, cleanerAttempted: attempted[0],
        cleanerRejected: rejected[0], cleanerMs: 0, transcribeMs: 1, processMs: 1, werPasses: wer,
        termHitPasses: terms, matchPasses: match, cleanerAttemptedPasses: attempted,
        cleanerRejectedPasses: rejected, finalPasses: finals)
}

@Test func summaryAveragesPerCaseOverPassesThenOverCases() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "c", audioDir: "a", peakMemoryMB: 1,
        cases: [
            passed(
                "d01", group: "dengl", wer: [0, 1], terms: [1, 0], match: [true, false], attempted: [true, true],
                rejected: [false, true], finals: ["x", "y"]),
            passed(
                "c01", group: "correction", wer: [0, 0], match: [true, true], attempted: [true, false],
                rejected: [false, false], finals: ["z", "z"]),
        ])
    let summary = RunSummary(run)
    #expect(summary.meanWER == 0.25)
    #expect(summary.termRate == 0.5)
    #expect(summary.denglTermRate == 0.5)
    #expect(summary.correctionRate == 1)
    // Three attempts over all passes, one rejected.
    #expect(abs((summary.cleanerRejectionRate ?? -1) - 1.0 / 3.0) < 0.0001)
    #expect(summary.unstableCases == 1)
}

@Test func legacyResultsWithoutPassArraysDecodeAndUseSingleValues() throws {
    let json = """
        {"date":"2026-01-01T00:00:00Z","transcriber":"t","cleaner":"none","audioDir":"a","peakMemoryMB":1,
         "loadMemoryMB":1,"cases":[{"id":"p01","group":"prose","raw":"a","final":"a","wer":0.5,"matchesExpected":true,
         "usedCleaner":false,"cleanerAttempted":false,"cleanerRejected":false,"cleanerMs":0,"transcribeMs":1,
         "processMs":1}]}
        """
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let run = try decoder.decode(RunResult.self, from: Data(json.utf8))
    #expect(run.cases[0].werPasses == nil)
    let summary = RunSummary(run)
    #expect(summary.meanWER == 0.5)
    #expect(summary.unstableCases == nil)
    #expect(BenchReport.markdown([summary]).split(separator: "\n").last?.contains("| - | 1 | 0 |") == true)
}

@Test func unstableColumnSitsBeforeCaseCount() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
        cases: [
            passed(
                "p01", group: "prose", wer: [0, 0], match: [true, true], attempted: [false, false],
                rejected: [false, false], finals: ["a", "b"])
        ])
    let table = BenchReport.markdown([RunSummary(run)])
    #expect(table.contains("| KI verworfen | instabil | Fälle |"))
    #expect(table.split(separator: "\n").last?.contains("| - | 1 | 1 | 0 |") == true, "\(table)")
}

private func timed(
    group: String = "prose", transcribe: [Double], attempted: [Bool]?, caseFlag: Bool
) -> CaseResult {
    CaseResult(
        id: "t01", group: group, raw: "", final: "", wer: 0, termHitRate: nil, matchesExpected: true,
        usedCleaner: false, cleanerAttempted: caseFlag, cleanerRejected: false, cleanerMs: 0,
        transcribeMs: transcribe[0], processMs: 1, transcribeSamplesMs: transcribe,
        processSamplesMs: Array(repeating: 1, count: transcribe.count), cleanerAttemptedPasses: attempted)
}

@Test func cleanerBucketsAreSplitPerSample() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "c", audioDir: "a", peakMemoryMB: 1,
        cases: [timed(group: "long", transcribe: [900, 100], attempted: [true, false], caseFlag: true)])
    let summary = RunSummary(run)
    #expect(summary.p95TotalWithCleanerMs == 901)
    #expect(summary.withCleanerSamples == 1)
    #expect(summary.p95TotalWithoutCleanerMs == 101)
    #expect(summary.withoutCleanerSamples == 1)
    #expect(summary.p95LongWithoutCleanerMs == 101)
    #expect(summary.longWithoutCleanerSamples == 1)
    #expect(summary.cleanerAttempts == 1)
}

@Test func cleanerBucketsFallBackToCaseFlagWhenCountsDiffer() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "c", audioDir: "a", peakMemoryMB: 1,
        cases: [
            timed(transcribe: [900, 800], attempted: [true], caseFlag: true),
            timed(transcribe: [100, 150], attempted: nil, caseFlag: false),
        ])
    let summary = RunSummary(run)
    #expect(summary.withCleanerSamples == 2)
    #expect(summary.withoutCleanerSamples == 2)
}

@Test func singlePassRunsShowDashForUnstable() {
    let run = RunResult(
        date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
        cases: [
            passed(
                "p01", group: "prose", wer: [0], match: [true], attempted: [false], rejected: [false],
                finals: ["a"])
        ])
    let summary = RunSummary(run)
    #expect(summary.unstableCases == nil)
    #expect(BenchReport.markdown([summary]).split(separator: "\n").last?.contains("| - | 1 | 0 |") == true)
}

@Test func failedLaterPassesAreShownNextToFailedCases() {
    func failedCase(_ id: String) -> CaseResult {
        CaseResult(
            id: id, group: "prose", raw: "", final: "", wer: 1, termHitRate: nil, matchesExpected: false,
            usedCleaner: false, cleanerAttempted: false, cleanerRejected: false, cleanerMs: 0, transcribeMs: 1,
            processMs: 0, error: "boom")
    }
    var ok = sample("a", group: "prose", wer: 0, terms: nil, match: true, cleaner: false, ms: 10)
    ok = CaseResult(
        id: ok.id, group: ok.group, raw: "", final: "", wer: 0, termHitRate: nil, matchesExpected: true,
        usedCleaner: false, cleanerAttempted: false, cleanerRejected: false, cleanerMs: 0, transcribeMs: 10,
        processMs: 1, failedLaterPasses: 3)
    let withLater = RunSummary(
        RunResult(
            date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
            cases: [ok, failedCase("b")]))
    #expect(withLater.errorCount == 1)
    #expect(withLater.failedLaterPasses == 3)
    #expect(BenchReport.markdown([withLater]).split(separator: "\n").last?.contains("| 1 | 1 (+3) |") == true)
    let without = RunSummary(
        RunResult(
            date: Date(), transcriber: "t", cleaner: "none", audioDir: "a", peakMemoryMB: 1,
            cases: [failedCase("b")]))
    #expect(BenchReport.markdown([without]).split(separator: "\n").last?.contains("| 0 | 1 |") == true)
}

@Test func footnoteExplainsCleanerColumnsAndFailures() {
    let note = BenchReport.footnote
    #expect(note.contains("ohne/mit KI"))
    #expect(note.contains("KI verworfen"))
    #expect(note.contains("X (+Y)"))
    #expect(note.contains("Schreibweise von Komposita"))
}
