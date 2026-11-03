import Darwin
import Foundation
import ZackCore

enum BenchError: Error, CustomStringConvertible {
    case warmUpFailed(String, String)
    case microphoneDenied
    case inputClosed

    var description: String {
        switch self {
        case .warmUpFailed(let engine, let reason): "warm-up of \(engine) failed: \(reason)"
        case .microphoneDenied:
            "no microphone access: allow your terminal app in System Settings > Privacy & Security > Microphone, then retry"
        case .inputClosed: "input closed, recording aborted"
        }
    }
}

/// Runs every corpus case with an audio file through one transcriber and one cleaner.
struct BenchRunner {
    /// Same digits as `String(format: "%.0f")`: no grouping, POSIX locale.
    static let wholeNumber = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0)).grouping(.never)
        .locale(Locale(identifier: "en_US_POSIX"))

    let corpus: Corpus
    let transcriber: any Transcriber
    let cleaner: (any Cleaner)?
    let audioDirectory: URL
    /// Timed round-robin passes over all cases; timings and quality come from every pass (raw/final shown: pass 1).
    var repeats = 5
    var language: DictationLanguage = .german
    var log: (String) -> Void = { print($0) }

    /// Timings and output of one case in one pass.
    private struct Pass {
        var raw = ""
        var failure: String?
        var processed: ProcessingResult?
        var transcribeMs: Double = 0
        var processMs: Double = 0
        var final: String { processed?.final ?? raw }
    }

    func run() async throws -> RunResult {
        // Model loading and first-call warm-up stay outside the timed passes.
        try await transcriber.prepare()
        try await cleaner?.prepare()
        let vocabulary = corpus.parsedVocabulary
        let processor = TextProcessor(vocabulary: vocabulary, snippets: corpus.parsedSnippets, cleaner: cleaner)

        let available = corpus.cases.compactMap { testCase -> (CorpusCase, AudioClip)? in
            let url = audioDirectory.appending(path: "\(testCase.id).wav")
            guard let data = try? Data(contentsOf: url), let clip = try? WAVFile.decode(data) else { return nil }
            return (testCase, clip)
        }
        guard let warmUp = available.first else {
            throw ZackError.engineUnavailable("no audio in \(audioDirectory.path)")
        }
        do {
            _ = try await transcriber.transcribe(warmUp.1, hints: vocabulary.terms)
        } catch { throw BenchError.warmUpFailed(transcriber.id, "\(error)") }
        if let cleaner {
            do {
                _ = try await cleaner.clean(
                    warmUp.0.spoken, mode: warmUp.0.mode, vocabulary: vocabulary.terms,
                    language: language)
            } catch { throw BenchError.warmUpFailed(cleaner.id, "\(error)") }
        }

        let loadFootprint = MemoryFootprint.currentMB()
        var peakFootprint = loadFootprint
        var firstPass: [Pass] = []
        var transcribeSamples = Array(repeating: [Double](), count: available.count)
        var processSamples = Array(repeating: [Double](), count: available.count)
        var passes = Array(repeating: [Pass](), count: available.count)
        var failedLater = Array(repeating: 0, count: available.count)
        for pass in 1...max(repeats, 1) {
            if repeats > 1 { log("pass \(pass)/\(repeats)") }
            for (index, (testCase, clip)) in available.enumerated() {
                // A case that failed in pass 1 has no quality data, so later passes skip it.
                if pass > 1, firstPass[index].failure != nil { continue }
                let current = await measure(clip, mode: testCase.mode, processor: processor, hints: vocabulary.terms)
                peakFootprint = max(peakFootprint, MemoryFootprint.currentMB())
                if pass == 1 {
                    firstPass.append(current)
                    if let failure = current.failure {
                        log("\(testCase.id)  FAILED: \(failure)")
                    } else {
                        let milliseconds = current.transcribeMs.formatted(Self.wholeNumber)
                        log("\(testCase.id)  \(milliseconds) ms  \(current.final)")
                    }
                } else if let failure = current.failure {
                    log("warning: pass \(pass) \(testCase.id) FAILED, no timing kept: \(failure)")
                    failedLater[index] += 1
                    continue
                } else if current.final != firstPass[index].final {
                    log("warning: pass \(pass) \(testCase.id) differs from pass 1: \(current.final)")
                }
                if current.failure == nil {
                    passes[index].append(current)
                    transcribeSamples[index].append(current.transcribeMs)
                    processSamples[index].append(current.processMs)
                }
            }
        }

        let results = available.enumerated().map { index, entry in
            caseResult(
                entry.0, firstPass[index], passes: passes[index], audioSeconds: entry.1.duration,
                transcribeSamples: transcribeSamples[index], processSamples: processSamples[index],
                failedLaterPasses: failedLater[index])
        }
        return RunResult(
            date: Date(), transcriber: transcriber.id, cleaner: cleaner?.id ?? "none",
            audioDir: audioDirectory.lastPathComponent, peakMemoryMB: peakFootprint,
            loadMemoryMB: loadFootprint,
            osBuild: ProcessInfo.processInfo.operatingSystemVersionString, cases: results)
    }

    private func measure(_ clip: AudioClip, mode: TextMode, processor: TextProcessor, hints: [String]) async -> Pass {
        let clock = ContinuousClock()
        var current = Pass()
        current.transcribeMs = await clock.measure {
            do {
                current.raw = try await transcriber.transcribe(clip, hints: hints)
            } catch {
                current.failure = "\(error)"
            }
        }.milliseconds
        guard current.failure == nil else { return current }
        let raw = current.raw
        var processed: ProcessingResult?
        current.processMs = await clock.measure {
            processed = await processor.process(raw, context: RuleContext(mode: mode, language: language))
        }.milliseconds
        current.processed = processed
        return current
    }

    private func caseResult(
        _ testCase: CorpusCase, _ pass: Pass, passes: [Pass], audioSeconds: Double, transcribeSamples: [Double],
        processSamples: [Double], failedLaterPasses: Int
    ) -> CaseResult {
        if let failure = pass.failure {
            return CaseResult(
                id: testCase.id, group: testCase.group, raw: "", final: "", wer: 1, termHitRate: nil,
                matchesExpected: false, usedCleaner: false, cleanerAttempted: false, cleanerRejected: false,
                cleanerMs: 0, transcribeMs: pass.transcribeMs, processMs: 0, error: failure, audioSeconds: audioSeconds)
        }
        let processed = pass.processed
        return CaseResult(
            id: testCase.id, group: testCase.group, raw: pass.raw, final: pass.final,
            wer: Metrics.wordErrorRate(reference: testCase.spoken, hypothesis: pass.raw, language: language),
            termHitRate: Metrics.termHitRate(terms: testCase.terms, in: pass.final),
            matchesExpected: Metrics.matches(expected: testCase.expected, actual: pass.final),
            usedCleaner: processed?.usedCleaner ?? false,
            cleanerAttempted: processed?.cleanerDuration != nil,
            cleanerRejected: processed?.cleanerRejected ?? false,
            cleanerMs: processed?.cleanerDuration?.milliseconds ?? 0,
            transcribeMs: pass.transcribeMs, processMs: pass.processMs,
            transcribeSamplesMs: transcribeSamples, processSamplesMs: processSamples, audioSeconds: audioSeconds,
            werPasses: passes.map {
                Metrics.wordErrorRate(reference: testCase.spoken, hypothesis: $0.raw, language: language)
            },
            termHitPasses: passes.compactMap { Metrics.termHitRate(terms: testCase.terms, in: $0.final) },
            matchPasses: passes.map { Metrics.matches(expected: testCase.expected, actual: $0.final) },
            cleanerAttemptedPasses: passes.map { $0.processed?.cleanerDuration != nil },
            cleanerRejectedPasses: passes.map { $0.processed?.cleanerRejected ?? false },
            finalPasses: passes.map(\.final), rawPasses: passes.map(\.raw), failedLaterPasses: failedLaterPasses)
    }
}

/// Physical footprint of this process (what Activity Monitor shows as memory), including GPU and Neural Engine
/// allocations charged to the process. Unlike max RSS it is not a lifetime high-water mark.
enum MemoryFootprint {
    static func currentMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Double(info.phys_footprint) / 1_048_576
    }
}

extension Duration {
    var milliseconds: Double {
        Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1e15
    }
}
