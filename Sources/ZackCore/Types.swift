/// Mono PCM audio. Engines expect 16 kHz.
public struct AudioClip: Sendable, Equatable {
    public let samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float], sampleRate: Double = 16_000) {
        self.samples = samples
        self.sampleRate = sampleRate
    }

    public var duration: Double { Double(samples.count) / sampleRate }
}

public enum TextMode: String, Sendable, Codable {
    case prose
    case code
}

public enum ZackError: Error, Equatable, Sendable {
    case unsupportedSampleRate(Double)
    case engineUnavailable(String)
    case unknownEngine(String)
    case audioFormat
    case timeout
    /// Model files are not on disk and the caller does not allow a download.
    case modelMissing(String)
    /// Input exceeds what the engine can handle in one call.
    case inputTooLong
}

/// Speech-to-text engine.
public protocol Transcriber: Sendable {
    var id: String { get }
    /// Loads or downloads models; called once before the first transcription.
    func prepare() async throws
    func transcribe(_ audio: AudioClip, hints: [String]) async throws -> String
}

/// Language-model based cleanup of a dictation.
public protocol Cleaner: Sendable {
    var id: String { get }
    func prepare() async throws
    func clean(_ text: String, mode: TextMode, vocabulary: [String], language: DictationLanguage) async throws
        -> String
    /// Readies a session for a cleanup that may follow; may be called repeatedly. The next `clean` with the same
    /// mode, vocabulary and language uses that session, once.
    func prewarm(mode: TextMode, vocabulary: [String], language: DictationLanguage)
    /// Drops a readied session that no cleanup took.
    func discardPrewarmed()
}

extension Transcriber {
    public func prepare() async throws {}
}

extension Cleaner {
    public func prepare() async throws {}
    public func prewarm(mode: TextMode, vocabulary: [String], language: DictationLanguage) {}
    public func discardPrewarmed() {}
}
