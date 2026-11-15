import Foundation
import ZackApple
import ZackCore
import ZackParakeet
import ZackWhisper

/// The term check's second opinion plus what the bench needs around it.
struct BenchCheck: Sendable {
    let id: String
    let opinion: any SecondOpinion
    /// Load and warm-up, outside the timings.
    let prepare: @Sendable () async throws -> Void
    /// Prompt tokens of the last call; nil if the engine does not report them.
    let lastPromptTokens: @Sendable () async -> Int?
}

enum Registry {
    static let transcriberIDs =
        AppleTranscriber.Kind.allCases.map(\.rawValue)
        + ParakeetTranscriber.Variant.allCases.map(\.rawValue)
    static let cleanerIDs = ["none", "apple-fm"]
    static let checkIDs = ["none", "whisper-terms"]

    /// `whisper-terms` loads the installed model from `ModelStorage`; the bench never downloads it.
    static func check(_ id: String) throws -> BenchCheck? {
        switch id {
        case "none": return nil
        case "whisper-terms":
            let engine = WhisperEngine(base: try ModelStorage.directory(createIfNeeded: false))
            return BenchCheck(
                id: engine.id, opinion: engine,
                prepare: {
                    try await engine.prepare()
                    try await engine.warmUp()
                }, lastPromptTokens: { await engine.lastPromptTokenCount })
        default: throw ArgumentError.invalidValue(option: "--check", value: id, allowed: checkIDs)
        }
    }

    static func transcriber(_ id: String, language: DictationLanguage = .german) throws -> any Transcriber {
        if let kind = AppleTranscriber.Kind(rawValue: id) {
            return AppleTranscriber(kind: kind, locale: Locale(identifier: language == .english ? "en-US" : "de-DE"))
        }
        if let variant = ParakeetTranscriber.Variant(rawValue: id) { return ParakeetTranscriber(variant: variant) }
        throw ArgumentError.invalidValue(option: "--transcriber", value: id, allowed: transcriberIDs)
    }

    static func cleaner(_ id: String) throws -> (any Cleaner)? {
        switch id {
        case "none": return nil
        case "apple-fm": return AppleFoundationCleaner()
        default: throw ArgumentError.invalidValue(option: "--cleaner", value: id, allowed: cleanerIDs)
        }
    }
}
