import Testing

@testable import ZackCore

/// Implements only `transcribe`, as engines without word confidences do.
private struct TextOnlyTranscriber: Transcriber {
    let id = "text-only"
    func prepare() async throws {}
    func transcribe(_ audio: AudioClip, hints: [String]) async throws -> String { "x" }
}

@Test func defaultRecognizeWrapsTranscribe() async throws {
    let recognition = try await TextOnlyTranscriber().recognize(AudioClip(samples: []), hints: [])
    #expect(recognition == Recognition(text: "x", words: []))
}

@Test func audioClipDurationFollowsSampleRate() {
    let clip = AudioClip(samples: Array(repeating: 0, count: 8_000))
    #expect(clip.sampleRate == 16_000)
    #expect(clip.duration == 0.5)
}
