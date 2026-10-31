import AVFoundation
import Testing
import ZackCore
import ZackTestSupport

@testable import ZackApple

@Suite(.enabled(if: Fixture.integration), .serialized)
struct AppleTranscriberTests {
    @Test(arguments: [AppleTranscriber.Kind.speech, .dictation])
    func transcribesGermanFixture(kind: AppleTranscriber.Kind) async throws {
        let engine = AppleTranscriber(kind: kind)
        try await engine.prepare()
        let text = try await engine.transcribe(try Fixture.hallo(), hints: ["Spracherkennung"])
        #expect(text.localizedCaseInsensitiveContains("Test"), "\(kind): \(text)")
        #expect(text.localizedCaseInsensitiveContains("Spracherkennung"), "\(kind): \(text)")
    }
}

/// The clip goes to SpeechAnalyzer as an in-memory buffer in the analyzer's format; needs no model.
@Suite struct AnalyzerBufferTests {
    static let clip = AudioClip(samples: (0..<8_000).map { Float(sin(Double($0) / 10)) * 0.5 })

    @Test func convertsToAnalyzerSampleFormat() throws {
        // Format reported by SpeechAnalyzer.bestAvailableAudioFormat on macOS 26 for both modules.
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true))
        let buffer = try AppleTranscriber.buffer(Self.clip, format: format)
        #expect(buffer.format == format)
        #expect(buffer.frameLength == 8_000)
        let samples = try #require(buffer.int16ChannelData)[0]
        for index in [0, 100, 4_321, 7_999] {
            #expect(abs(Int(samples[index]) - Int(Self.clip.samples[index] * 32_767)) <= 1, "\(index)")
        }
    }

    @Test func resamplesWithoutDroppingTheEnd() throws {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false))
        let buffer = try AppleTranscriber.buffer(Self.clip, format: format)
        #expect(abs(Int(buffer.frameLength) - 24_000) <= 16, "\(buffer.frameLength)")
    }

    @Test func matchingFormatKeepsSamples() throws {
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false))
        let buffer = try AppleTranscriber.buffer(Self.clip, format: format)
        let samples = try #require(buffer.floatChannelData)[0]
        #expect(Array(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))) == Self.clip.samples)
    }
}
