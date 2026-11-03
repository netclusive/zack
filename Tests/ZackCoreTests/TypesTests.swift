import Testing

@testable import ZackCore

@Test func audioClipDurationFollowsSampleRate() {
    let clip = AudioClip(samples: Array(repeating: 0, count: 8_000))
    #expect(clip.sampleRate == 16_000)
    #expect(clip.duration == 0.5)
}
