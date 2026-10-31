import Foundation
import ZackCore

public struct CaseResult: Codable, Sendable {
    public let id: String
    public let group: String
    public let raw: String
    public let final: String
    public let wer: Double
    /// nil if the case has no terms.
    public let termHitRate: Double?
    public let matchesExpected: Bool
    /// Cleaner output was accepted and used.
    public let usedCleaner: Bool
    /// Cleaner was called (accepted, rejected or timed out).
    public let cleanerAttempted: Bool
    public let cleanerRejected: Bool
    public let cleanerMs: Double
    public let transcribeMs: Double
    public let processMs: Double
    /// Set if the transcription failed; such cases are excluded from the aggregates.
    public let error: String?
    /// Transcription time of every timed pass, pass 1 first; nil in runs before `--repeat`.
    public let transcribeSamplesMs: [Double]?
    /// Processing time of every timed pass, aligned with `transcribeSamplesMs`.
    public let processSamplesMs: [Double]?
    /// Length of the recording; nil in old runs.
    public let audioSeconds: Double?
    /// Per-pass quality of the passes that succeeded, pass 1 first; nil in runs before quality averaging.
    public let werPasses: [Double]?
    /// Term hit rate per pass; empty if the case has no terms.
    public let termHitPasses: [Double]?
    public let matchPasses: [Bool]?
    public let cleanerAttemptedPasses: [Bool]?
    /// Aligned with `cleanerAttemptedPasses`.
    public let cleanerRejectedPasses: [Bool]?
    public let finalPasses: [String]?
    /// Raw transcription per successful pass, aligned with `finalPasses`, so metrics can be recomputed later.
    public let rawPasses: [String]?
    /// Later passes whose transcription failed (logged and dropped); nil in older runs.
    public let failedLaterPasses: Int?

    public init(
        id: String, group: String, raw: String, final: String, wer: Double, termHitRate: Double?,
        matchesExpected: Bool, usedCleaner: Bool, cleanerAttempted: Bool, cleanerRejected: Bool, cleanerMs: Double,
        transcribeMs: Double, processMs: Double, error: String? = nil, transcribeSamplesMs: [Double]? = nil,
        processSamplesMs: [Double]? = nil, audioSeconds: Double? = nil, werPasses: [Double]? = nil,
        termHitPasses: [Double]? = nil, matchPasses: [Bool]? = nil, cleanerAttemptedPasses: [Bool]? = nil,
        cleanerRejectedPasses: [Bool]? = nil, finalPasses: [String]? = nil, rawPasses: [String]? = nil,
        failedLaterPasses: Int? = nil
    ) {
        self.id = id
        self.group = group
        self.raw = raw
        self.final = final
        self.wer = wer
        self.termHitRate = termHitRate
        self.matchesExpected = matchesExpected
        self.usedCleaner = usedCleaner
        self.cleanerAttempted = cleanerAttempted
        self.cleanerRejected = cleanerRejected
        self.cleanerMs = cleanerMs
        self.transcribeMs = transcribeMs
        self.processMs = processMs
        self.error = error
        self.transcribeSamplesMs = transcribeSamplesMs
        self.processSamplesMs = processSamplesMs
        self.audioSeconds = audioSeconds
        self.werPasses = werPasses
        self.termHitPasses = termHitPasses
        self.matchPasses = matchPasses
        self.cleanerAttemptedPasses = cleanerAttemptedPasses
        self.cleanerRejectedPasses = cleanerRejectedPasses
        self.finalPasses = finalPasses
        self.rawPasses = rawPasses
        self.failedLaterPasses = failedLaterPasses
    }

    /// Quality values of every pass; old runs have only the one of pass 1.
    var allWER: [Double] { werPasses ?? [wer] }
    var allTermHitRates: [Double] { termHitPasses ?? termHitRate.map { [$0] } ?? [] }
    var allMatches: [Bool] { matchPasses ?? [matchesExpected] }
    var allCleanerAttempts: [Bool] { cleanerAttemptedPasses ?? [cleanerAttempted] }
    var allCleanerRejections: [Bool] { cleanerRejectedPasses ?? [cleanerRejected] }

    /// Final text differs between passes; nil in old runs and with fewer than two passes.
    var isUnstable: Bool? {
        guard let finalPasses, finalPasses.count >= 2 else { return nil }
        return Set(finalPasses).count > 1
    }

    /// Pass 1 total; quality fields belong to this pass.
    public var totalMs: Double { transcribeMs + processMs }

    /// Every transcription timing; old runs have only the one of pass 1.
    public var transcribeSamples: [Double] { transcribeSamplesMs ?? [transcribeMs] }

    /// Every total timing (transcription plus processing of the same pass).
    public var totalSamples: [Double] {
        zip(transcribeSamples, processSamplesMs ?? [processMs]).map(+)
    }

    /// Total timings split by whether the cleaner ran in that pass. Falls back to the case flag for legacy runs
    /// or if the per-pass data does not line up with the timings.
    var totalSamplesByCleaner: (with: [Double], without: [Double]) {
        let totals = totalSamples
        guard let attempted = cleanerAttemptedPasses, attempted.count == totals.count else {
            return cleanerAttempted ? (totals, []) : ([], totals)
        }
        let pairs = zip(totals, attempted)
        return (pairs.filter(\.1).map(\.0), pairs.filter { !$0.1 }.map(\.0))
    }
}

public struct RunResult: Codable, Sendable {
    public let date: Date
    public let transcriber: String
    public let cleaner: String
    public let audioDir: String
    /// Peak physical footprint sampled during the timed loop.
    public let peakMemoryMB: Double
    /// Physical footprint after model load and warm-up.
    public let loadMemoryMB: Double
    /// OS version string including the build (Apple's on-device models change with OS updates); nil in old runs.
    public let osBuild: String?
    public let cases: [CaseResult]

    public init(
        date: Date, transcriber: String, cleaner: String, audioDir: String, peakMemoryMB: Double,
        loadMemoryMB: Double = 0, osBuild: String? = nil,
        cases: [CaseResult]
    ) {
        self.date = date
        self.transcriber = transcriber
        self.cleaner = cleaner
        self.audioDir = audioDir
        self.peakMemoryMB = peakMemoryMB
        self.loadMemoryMB = loadMemoryMB
        self.osBuild = osBuild
        self.cases = cases
    }
}

public struct RunSummary: Sendable {
    public let run: RunResult
    public let meanWER: Double?
    public let termRate: Double?
    public let denglTermRate: Double?
    public let correctionRate: Double?
    public let p50TranscribeMs: Double?
    public let p95TranscribeMs: Double?
    public let p95TotalWithoutCleanerMs: Double?
    /// p95 of the long (about 10 s) cases without cleaner; the design's latency target.
    public let p95LongWithoutCleanerMs: Double?
    public let p95TotalWithCleanerMs: Double?
    /// Number of timings behind each percentile (cases times passes).
    public let transcribeSamples: Int
    public let withoutCleanerSamples: Int
    public let longWithoutCleanerSamples: Int
    public let withCleanerSamples: Int
    /// Cases without errors, the base of every aggregate.
    public let caseCount: Int
    /// Mean recording length of the long cases, to check the 10 s of the latency target; nil if unknown.
    public let meanLongSeconds: Double?
    public let errorCount: Int
    /// Later passes that failed, over all cases.
    public let failedLaterPasses: Int
    public let cleanerAttempts: Int
    /// Rejected or timed-out share of cleaner attempts; nil if the cleaner never ran.
    public let cleanerRejectionRate: Double?
    /// Cases whose final text differs between passes; nil if no case has per-pass data (old runs).
    public let unstableCases: Int?

    public init(_ run: RunResult) {
        self.run = run
        errorCount = run.cases.filter { $0.error != nil }.count
        let cases = run.cases.filter { $0.error == nil }
        caseCount = cases.count
        failedLaterPasses = run.cases.compactMap(\.failedLaterPasses).reduce(0, +)
        func mean(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        func optionalMean(_ values: [Double]) -> Double? { values.isEmpty ? nil : mean(values) }
        func optionalPercentile(_ values: [Double], _ p: Double) -> Double? {
            values.isEmpty ? nil : Metrics.percentile(values, p)
        }
        // Per case the mean over its passes, then the mean over cases.
        meanWER = optionalMean(cases.map { mean($0.allWER) })
        meanLongSeconds = optionalMean(cases.filter { $0.group == "long" }.compactMap(\.audioSeconds))
        func termRate(_ cases: [CaseResult]) -> Double? {
            optionalMean(cases.compactMap { optionalMean($0.allTermHitRates) })
        }
        self.termRate = termRate(cases)
        denglTermRate = termRate(cases.filter { $0.group == "dengl" })
        correctionRate = optionalMean(
            cases.filter { $0.group == "correction" }.map { mean($0.allMatches.map { $0 ? 1 : 0 }) })
        let transcribe = cases.flatMap(\.transcribeSamples)
        let split = cases.map { ($0, $0.totalSamplesByCleaner) }
        let withoutCleaner = split.flatMap(\.1.without)
        let longWithoutCleaner = split.filter { $0.0.group == "long" }.flatMap(\.1.without)
        let withCleaner = split.flatMap(\.1.with)
        p50TranscribeMs = optionalPercentile(transcribe, 50)
        p95TranscribeMs = optionalPercentile(transcribe, 95)
        p95TotalWithoutCleanerMs = optionalPercentile(withoutCleaner, 95)
        p95LongWithoutCleanerMs = optionalPercentile(longWithoutCleaner, 95)
        p95TotalWithCleanerMs = optionalPercentile(withCleaner, 95)
        transcribeSamples = transcribe.count
        withoutCleanerSamples = withoutCleaner.count
        longWithoutCleanerSamples = longWithoutCleaner.count
        withCleanerSamples = withCleaner.count
        // Attempts and rejections over all passes of all cases.
        let passAttempts = cases.flatMap { zip($0.allCleanerAttempts, $0.allCleanerRejections) }.filter(\.0)
        cleanerAttempts = passAttempts.count
        cleanerRejectionRate =
            passAttempts.isEmpty ? nil : Double(passAttempts.filter(\.1).count) / Double(passAttempts.count)
        let unstableFlags = cases.compactMap(\.isUnstable)
        unstableCases = unstableFlags.isEmpty ? nil : unstableFlags.filter { $0 }.count
    }
}

public enum BenchReport {
    public static let footnote =
        "WER ist der Mittelwert über die Fälle (nicht über Wörter); fehlgeschlagene Fälle sind ausgeschlossen. Begriffe und Denglisch zählen nur Fälle mit Begriffen. WER und Korrekturen ignorieren die Schreibweise von Komposita (Bindestrich, getrennt, zusammen). Fälle zählt die ausgewerteten Fälle ohne Fehler. Fehler zeigt X (+Y): X fehlgeschlagene Fälle, Y fehlgeschlagene spätere Durchläufe. p95 10 s nutzt die Fälle der Gruppe long (je etwa 10 s Sprache), Ø lang s ist deren mittlere Aufnahmedauer in Sekunden. Latenzen sind Perzentile über alle Messungen aller Durchläufe (--repeat), n = Anzahl der Messungen; ohne/mit KI trennt die Messungen danach, ob der Glätter aufgerufen wurde oder nicht; Qualitätswerte sind über alle Durchläufe gemittelt. KI verworfen ist der Anteil verworfener oder abgelaufener Glätter-Aufrufe über alle Durchläufe. instabil zählt die Fälle, deren Endtext zwischen den Durchläufen abweicht. Speicher misst nur diesen Prozess: Apple Speech (n/a) und das Apple-Sprachmodell (apple-fm) laufen außerhalb des Prozesses, ihr Speicher ist nicht enthalten. - = keine Daten."

    /// Newest run per (transcriber, cleaner, audio directory) combination.
    public static func latest(_ runs: [RunResult]) -> [RunResult] {
        var newest: [String: RunResult] = [:]
        for run in runs {
            let key = "\(run.transcriber)|\(run.cleaner)|\(run.audioDir)"
            if let existing = newest[key], existing.date >= run.date { continue }
            newest[key] = run
        }
        return newest.values.sorted {
            ($0.audioDir, $0.transcriber, $0.cleaner) < ($1.audioDir, $1.transcriber, $1.cleaner)
        }
    }

    public static func markdown(_ summaries: [RunSummary]) -> String {
        var lines = [
            "| Erkennung | Glättung | Audio | WER | Begriffe | Denglisch | Korrekturen | p50 Erk. ms | p95 Erk. ms | p95 ohne KI ms | p95 10 s ohne KI ms | Ø lang s | p95 mit KI ms | KI verworfen | instabil | Fälle | Fehler | Speicher Laden MB | Speicher Lauf MB |",
            "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
        ]
        let ordered = summaries.sorted {
            $0.run.audioDir != $1.run.audioDir
                ? $0.run.audioDir < $1.run.audioDir : ($0.termRate ?? -1) > ($1.termRate ?? -1)
        }
        for s in ordered {
            let quality: [String] = [
                s.meanWER.map(percent) ?? "-", s.termRate.map(percent) ?? "-",
                s.denglTermRate.map(percent) ?? "-", s.correctionRate.map(percent) ?? "-",
            ]
            let latency: [String] = [
                latency(s.p50TranscribeMs, n: s.transcribeSamples),
                latency(s.p95TranscribeMs, n: s.transcribeSamples),
                latency(s.p95TotalWithoutCleanerMs, n: s.withoutCleanerSamples),
                latency(s.p95LongWithoutCleanerMs, n: s.longWithoutCleanerSamples),
                s.meanLongSeconds.map { String(format: "%.1f", $0) } ?? "-",
                latency(s.p95TotalWithCleanerMs, n: s.withCleanerSamples),
            ]
            let rest: [String] = [
                s.cleanerRejectionRate.map(percent) ?? "-", s.unstableCases.map(String.init) ?? "-",
                String(s.caseCount),
                s.failedLaterPasses > 0 ? "\(s.errorCount) (+\(s.failedLaterPasses))" : String(s.errorCount),
                memory(s.run.loadMemoryMB, for: s.run), memory(s.run.peakMemoryMB, for: s.run),
            ]
            let cells = [s.run.transcriber, s.run.cleaner, s.run.audioDir] + quality + latency + rest
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        var osBuilds: [String] = []
        for case let build? in ordered.map(\.run.osBuild) where !osBuilds.contains(build) { osBuilds.append(build) }
        if !osBuilds.isEmpty { lines += ["", "macOS: " + osBuilds.joined(separator: ", ")] }
        return lines.joined(separator: "\n")
    }

    /// Apple Speech runs out of process, so the footprint of this process says nothing about it.
    private static func memory(_ value: Double, for run: RunResult) -> String {
        run.transcriber.hasPrefix("apple-") ? "n/a" : int(value)
    }

    /// Milliseconds with the number of timings behind them, e.g. `57 (n=220)`.
    private static func latency(_ value: Double?, n: Int) -> String {
        value.map { "\(int($0)) (n=\(n))" } ?? "-"
    }

    private static func percent(_ value: Double) -> String { String(format: "%.1f %%", value * 100) }
    private static func int(_ value: Double) -> String { String(Int(value.rounded())) }
}
