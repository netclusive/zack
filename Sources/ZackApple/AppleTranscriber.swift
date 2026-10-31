import AVFoundation
import Foundation
import Speech
import ZackCore

/// On-device recognition via SpeechAnalyzer (macOS 26+), as general transcription or dictation module.
public struct AppleTranscriber: Transcriber {
    public enum Kind: String, Sendable, CaseIterable {
        case speech = "apple-speech"
        case dictation = "apple-dictation"
    }

    public let kind: Kind
    public let locale: Locale
    public var id: String { kind.rawValue }

    public init(kind: Kind, locale: Locale = Locale(identifier: "de-DE")) {
        self.kind = kind
        self.locale = locale
    }

    public func prepare() async throws {
        var supported: Locale?
        switch kind {
        case .speech: supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale)
        case .dictation: supported = await DictationTranscriber.supportedLocale(equivalentTo: locale)
        }
        guard supported != nil else { throw ZackError.engineUnavailable("\(id): locale \(locale.identifier)") }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [makeModule()]) {
            try await request.downloadAndInstall()
        }
    }

    public func transcribe(_ audio: AudioClip, hints: [String]) async throws -> String {
        guard audio.sampleRate == 16_000 else { throw ZackError.unsupportedSampleRate(audio.sampleRate) }
        // An empty clip makes SpeechAnalyzer hang forever; too short clips cannot yield text anyway.
        guard audio.duration >= EngineLimits.minimumClipDuration else { return "" }
        // Silence and near-silence make models invent text (Whisper: "Vielen Dank.").
        guard !EngineLimits.isSilent(audio) else { return "" }
        let context = AnalysisContext()
        if !hints.isEmpty { context.contextualStrings[.general] = hints }

        switch kind {
        case .speech:
            let module = SpeechTranscriber(locale: locale, preset: .transcription)
            let text = try await analyze(audio, module: module, context: context) {
                var text = ""
                for try await result in module.results where result.isFinal {
                    text += String(result.text.characters)
                }
                return text
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .dictation:
            let module = DictationTranscriber(locale: locale, preset: .shortDictation)
            let text = try await analyze(audio, module: module, context: context) {
                // shortDictation never reports final results, so volatile segments are kept by range start.
                var segments = DictationSegments()
                for try await result in module.results {
                    let text = String(result.text.characters)
                    if result.isFinal {
                        segments.addFinal(text)
                    } else {
                        segments.addVolatile(text, start: result.range.start.seconds)
                    }
                }
                return segments.text
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// Streams the clip from memory into a new analyzer (audio never touches the disk) and returns what `collect`
    /// read from the module's results, which end once the analyzer finished.
    private func analyze(
        _ audio: AudioClip, module: any SpeechModule, context: AnalysisContext,
        collect: @escaping @Sendable () async throws -> String
    ) async throws -> String {
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [module]) else {
            throw ZackError.audioFormat
        }
        let (input, builder) = AsyncStream<AnalyzerInput>.makeStream()
        builder.yield(AnalyzerInput(buffer: try Self.buffer(audio, format: format)))
        builder.finish()

        let options = SpeechAnalyzer.Options(priority: .userInitiated, modelRetention: .processLifetime)
        let analyzer = SpeechAnalyzer(modules: [module], options: options)
        try await analyzer.setContext(context)
        async let text = collect()
        do {
            try await analyzer.start(inputSequence: input)
            // Finalizes the volatile tail (the last words) and ends the results.
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        } catch {
            // Ends the results, so awaiting `text` cannot hang.
            await analyzer.cancelAndFinishNow()
            throw error
        }
        return try await text
    }

    /// The clip as one PCM buffer in `format`, converted if needed.
    static func buffer(_ audio: AudioClip, format: AVAudioFormat) throws -> AVAudioPCMBuffer {
        guard
            let source = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: audio.sampleRate, channels: 1, interleaved: false),
            let clip = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: AVAudioFrameCount(audio.samples.count)),
            let channel = clip.floatChannelData?[0]
        else { throw ZackError.audioFormat }
        audio.samples.withUnsafeBufferPointer { samples in
            if let base = samples.baseAddress { channel.update(from: base, count: samples.count) }
        }
        clip.frameLength = clip.frameCapacity
        if format == source { return clip }

        let ratio = format.sampleRate / source.sampleRate
        // Slack for resampler rounding.
        let capacity = AVAudioFrameCount((Double(clip.frameLength) * ratio).rounded(.up)) + 1_024
        guard let converter = AVAudioConverter(from: source, to: format),
            let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity)
        else { throw ZackError.audioFormat }
        var delivered = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            // One input buffer, then end of stream, so the converter flushes everything.
            guard !delivered else {
                inputStatus.pointee = .endOfStream
                return nil
            }
            delivered = true
            inputStatus.pointee = .haveData
            return clip
        }
        guard status != .error, error == nil else { throw ZackError.audioFormat }
        return output
    }

    private func makeModule() -> any SpeechModule {
        switch kind {
        case .speech: SpeechTranscriber(locale: locale, preset: .transcription)
        case .dictation: DictationTranscriber(locale: locale, preset: .shortDictation)
        }
    }
}
