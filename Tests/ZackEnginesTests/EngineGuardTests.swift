import Testing
import ZackApple
import ZackCore
import ZackParakeet
import ZackTestSupport

/// Input guards that run before any model or asset work, so no models are needed.
@Suite(.timeLimit(.minutes(1)))
struct EngineGuardTests {
    static let engines: [any Transcriber] = [
        AppleTranscriber(kind: .speech),
        AppleTranscriber(kind: .dictation),
        ParakeetTranscriber(variant: .v3),
        ParakeetTranscriber(variant: .ultra),
    ]

    @Test(arguments: engines.map(\.id))
    func emptyClipReturnsEmptyText(id: String) async throws {
        let engine = try #require(Self.engines.first { $0.id == id })
        let text = try await engine.transcribe(AudioClip(samples: []), hints: [])
        #expect(text == "")
    }

    @Test(arguments: engines.map(\.id))
    func clipBelowMinimumDurationReturnsEmptyText(id: String) async throws {
        let engine = try #require(Self.engines.first { $0.id == id })
        let justBelow = Int(16_000 * EngineLimits.minimumClipDuration) - 1
        let text = try await engine.transcribe(AudioClip(samples: Array(repeating: 0.1, count: justBelow)), hints: [])
        #expect(text == "")
    }

    @Test(arguments: engines.map(\.id))
    func silentClipReturnsEmptyText(id: String) async throws {
        let engine = try #require(Self.engines.first { $0.id == id })
        let text = try await engine.transcribe(AudioClip(samples: Array(repeating: 0, count: 16_000)), hints: [])
        #expect(text == "")
    }

    @Test(arguments: engines.map(\.id))
    func lowNoiseClipReturnsEmptyText(id: String) async throws {
        let engine = try #require(Self.engines.first { $0.id == id })
        let noise = (0..<48_000).map { _ in Float.random(in: -0.002...0.002) }
        let text = try await engine.transcribe(AudioClip(samples: noise), hints: [])
        #expect(text == "")
    }

    @Test func quietSpeechIsNotSilent() throws {
        expectQuietSpeechIsNotSilent(try Fixture.hallo())
        #expect(EngineLimits.isSilent(AudioClip(samples: Array(repeating: 0, count: 16_000))))
    }

    /// The result must not depend on the German system voice; skipped without a German voice other than Anna.
    @Test(.enabled(if: try Fixture.otherGermanVoice() != nil))
    func quietSpeechInAnotherVoiceIsNotSilent() throws {
        let voice = try #require(try Fixture.otherGermanVoice())
        expectQuietSpeechIsNotSilent(try Fixture.hallo(voice: voice), voice: voice)
    }

    /// Scales the speech to the level the thresholds were tuned on (Anna: RMS 0.1165 at gain 1), since voices differ
    /// in loudness; the shared fixture stays unscaled, so engines never get samples above 1.
    private func expectQuietSpeechIsNotSilent(_ speech: AudioClip, voice: String = "default") {
        let rms = (speech.samples.reduce(0) { $0 + $1 * $1 } / Float(speech.samples.count)).squareRoot()
        let level = 0.1165 / rms
        for gain: Float in [1, 0.1, 0.05, 0.02] {
            // A plain Bool, so a failure does not print every sample.
            let silent = EngineLimits.isSilent(AudioClip(samples: speech.samples.map { $0 * gain * level }))
            #expect(!silent, "voice \(voice), gain \(gain)")
        }
    }

    @Test(arguments: engines.map(\.id))
    func rejectsWrongSampleRate(id: String) async throws {
        let engine = try #require(Self.engines.first { $0.id == id })
        await #expect(throws: ZackError.unsupportedSampleRate(44_100)) {
            try await engine.transcribe(AudioClip(samples: [0], sampleRate: 44_100), hints: [])
        }
    }
}
