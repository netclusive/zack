import FluidAudio
import Foundation
import ZackCore

/// Parakeet TDT on the Neural Engine via FluidAudio. Models come from `ModelPolicy`: the bench downloads on first use, the app only loads local copies.
public actor ParakeetTranscriber: Transcriber {
    public enum Variant: String, Sendable, CaseIterable {
        case v3 = "parakeet-v3"
        case ultra = "parakeet-ultra"
    }

    /// What happens if the model is not on disk.
    public enum ModelPolicy: Sendable {
        /// zack-bench: download from Hugging Face on first use.
        case downloadIfMissing
        /// App: load complete local models only, never touch the network.
        case localOnly
    }

    public nonisolated let variant: Variant
    public nonisolated var id: String { variant.rawValue }
    /// Nil: `ModelStorage.directory`.
    public nonisolated let modelsDirectory: URL?
    public nonisolated let policy: ModelPolicy
    private var loading: Task<AsrManager, any Error>?
    /// Number of model loads started, for tests.
    private(set) var loadCount = 0

    public init(variant: Variant, modelsDirectory: URL? = nil, policy: ModelPolicy = .downloadIfMissing) {
        self.variant = variant
        self.modelsDirectory = modelsDirectory
        self.policy = policy
    }

    public func prepare() async throws {
        _ = try await loadedManager()
    }

    /// Transcribes one second of a synthetic tone, so the first dictation does not pay for the first inference.
    public func warmUp() async throws {
        let tone = (0..<16_000).map { 0.1 * sin(2 * Float.pi * 440 * Float($0) / 16_000) }
        _ = try await transcribe(AudioClip(samples: tone), hints: [])
    }

    /// Single in-flight load shared by all callers; a failed load is dropped so a retry is possible.
    private func loadedManager() async throws -> AsrManager {
        if let loading { return try await loading.value }
        loadCount += 1
        let variant = variant
        let policy = policy
        let base = try modelsDirectory ?? ModelStorage.directory(createIfNeeded: true)
        let task = Task { try await Self.load(variant, from: base, policy: policy) }
        loading = task
        do {
            return try await task.value
        } catch {
            loading = nil
            throw error
        }
    }

    /// Where `.downloadIfMissing` gets its models from.
    enum Source: Equatable {
        /// A complete copy in this models directory.
        case local(URL)
        /// No complete copy exists; download into this models directory.
        case download(URL)
    }

    /// Complete copy in `base` first, then in FluidAudio's cache (before 0.2.0), else download into `base`.
    static func source(for variant: Variant, base: URL, legacy: URL) -> Source {
        if ParakeetModelStore.isComplete(variant, in: base) { return .local(base) }
        if ParakeetModelStore.isComplete(variant, in: legacy) { return .local(legacy) }
        return .download(base)
    }

    private static func load(_ variant: Variant, from base: URL, policy: ModelPolicy) async throws -> AsrManager {
        let models: AsrModels
        switch policy {
        case .localOnly:
            guard ParakeetModelStore.isComplete(variant, in: base) else {
                throw ZackError.modelMissing(variant.rawValue)
            }
            models = try ParakeetModelStore.loadLocal(variant, from: base)
        case .downloadIfMissing:
            // Never `AsrModels.load`/`downloadAndLoad`: after a load error they purge the cache and download again.
            let legacy = ParakeetModelStore.fluidAudioDirectory()
            switch source(for: variant, base: base, legacy: legacy) {
            case .local(let directory):
                models = try ParakeetModelStore.loadLocal(variant, from: directory)
            case .download(let directory):
                try await ParakeetModelStore.download(variant, to: directory) { _ in }
                models = try ParakeetModelStore.loadLocal(variant, from: directory)
            }
        }
        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)
        return manager
    }

    public func transcribe(_ audio: AudioClip, hints: [String]) async throws -> String {
        guard audio.sampleRate == 16_000 else { throw ZackError.unsupportedSampleRate(audio.sampleRate) }
        // FluidAudio throws invalidAudioData below its minimum; treat such clips as silence.
        guard audio.duration >= EngineLimits.minimumClipDuration else { return "" }
        // Silence and near-silence make models invent text (Whisper: "Vielen Dank.").
        guard !EngineLimits.isSilent(audio) else { return "" }
        let manager = try await loadedManager()
        // Fresh decoder state per call: every dictation is independent.
        var decoderState = TdtDecoderState.make()
        let result = try await manager.transcribe(audio.samples, decoderState: &decoderState)
        return result.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
