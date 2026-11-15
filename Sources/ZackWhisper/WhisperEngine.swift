import Foundation
import WhisperKit
import ZackCore

/// Whisper large-v3 turbo as the term check's second opinion. Loads only a local, complete model; never downloads.
public actor WhisperEngine: SecondOpinion {
    public nonisolated let id = "whisper-terms"
    /// Prompt tokens of the last `recognize`, for the bench log.
    public private(set) var lastPromptTokenCount = 0
    private let base: URL
    private var pipe: WhisperKit?
    private var loading: Task<Void, any Error>?

    /// `base`: the models directory that holds the hub folders (`ModelStorage.directory`).
    public init(base: URL) {
        self.base = base
    }

    /// Loads the model from disk; `ZackError.modelMissing` if a file is absent. Concurrent calls share one load.
    public func prepare() async throws {
        guard pipe == nil else { return }
        if let loading { return try await loading.value }
        guard WhisperModelStore.isComplete(in: base) else { throw ZackError.modelMissing(id) }
        // WhisperKit fetches the tokenizer from the hub when the local load fails; a changed file stops here instead.
        try ModelManifest.verify(WhisperModelManifest.tokenizer, in: WhisperModelStore.tokenizerFolder(in: base))
        let task = Task { try await load() }
        loading = task
        defer { loading = nil }
        try await task.value
    }

    private func load() async throws {
        let config = WhisperKitConfig(
            model: WhisperModelManifest.variant, downloadBase: base,
            modelFolder: WhisperModelStore.modelFolder(in: base).path, tokenizerFolder: base, verbose: false,
            logLevel: .none, load: true, download: false)
        pipe = try await WhisperKit(config)
    }

    /// One short decode, so the first dictation does not pay for Core ML's specialization.
    public func warmUp() async throws {
        guard let pipe else { throw ZackError.engineUnavailable(id) }
        let tone = (0..<16_000).map { Float(sin(Double($0) * 0.05)) * 0.1 }
        _ = try await pipe.transcribe(audioArray: tone, decodeOptions: Self.options(language: .german))
    }

    /// Drops the pipeline; a running `recognize` keeps its own reference and ends normally.
    public func unload() async {
        pipe = nil
    }

    public func recognize(_ audio: AudioClip, terms: [String], focus: [String], language: DictationLanguage)
        async throws -> String
    {
        guard audio.sampleRate == 16_000 else { throw ZackError.unsupportedSampleRate(audio.sampleRate) }
        guard let pipe else { throw ZackError.engineUnavailable(id) }
        guard audio.duration >= EngineLimits.minimumClipDuration else { return "" }
        // Silence and near-silence make Whisper invent text ("Vielen Dank.").
        guard !EngineLimits.isSilent(audio) else { return "" }
        var options = Self.options(language: language)
        if let tokenizer = pipe.tokenizer {
            let prompt = Self.promptTokens(
                terms: terms, focus: focus, encode: { tokenizer.encode(text: $0) },
                specialBegin: tokenizer.specialTokens.specialTokenBegin)
            options.promptTokens = prompt.isEmpty ? nil : prompt
            lastPromptTokenCount = prompt.count
        }
        let results = try await pipe.transcribe(audioArray: audio.samples, decodeOptions: options)
        return results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// As WhisperKit's CLI builds `--prompt`: leading space, terms joined by ", ", special tokens dropped; the terms
    /// are chosen to fit `TermPrompt.tokenBudget`, so WhisperKit never cuts the prompt itself.
    static func promptTokens(terms: [String], focus: [String], encode: (String) -> [Int], specialBegin: Int) -> [Int] {
        func tokens(_ selection: [String]) -> [Int] {
            guard !selection.isEmpty else { return [] }
            return encode(" " + selection.joined(separator: ", ")).filter { $0 < specialBegin }
        }
        return tokens(TermPrompt.select(terms, focus: focus, tokens: { tokens($0).count }))
    }

    /// Language forced, no detection; thresholds are OpenAI's defaults, set explicitly as in the 2026-11-14 probe.
    private static func options(language: DictationLanguage) -> DecodingOptions {
        DecodingOptions(
            language: language.rawValue, detectLanguage: false, withoutTimestamps: true,
            compressionRatioThreshold: 2.4, logProbThreshold: -1.0, noSpeechThreshold: 0.6)
    }
}
