import Testing

@testable import ZackCore

@Test func audioClipDurationFollowsSampleRate() {
    let clip = AudioClip(samples: Array(repeating: 0, count: 8_000))
    #expect(clip.sampleRate == 16_000)
    #expect(clip.duration == 0.5)
}

@Test func defaultPrepareDoesNothing() async throws {
    struct Echo: Transcriber {
        let id = "echo"
        func transcribe(_ audio: AudioClip, hints: [String]) async throws -> String { "ok" }
    }
    try await Echo().prepare()
    #expect(try await Echo().transcribe(AudioClip(samples: []), hints: []) == "ok")
}
