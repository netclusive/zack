@preconcurrency import AVFoundation
import CoreAudio
import Foundation
import Testing

@testable import ZackDesktop

/// The first input device whose hardware rate differs from the engine's processing rate; the engine is not started.
func mismatchingInputDevice() -> AudioObjectID? {
    for device in AudioDevices.inputDevices() {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        guard (try? input.auAudioUnit.setDeviceID(device.id)) != nil else { continue }
        if input.inputFormat(forBus: 0).sampleRate != input.outputFormat(forBus: 0).sampleRate {
            return device.id
        }
    }
    return nil
}

/// Records through `MicrophoneCapture` for at most 2 s and returns the sample count; always stops the capture.
private func recordedSamples(device: @escaping @Sendable () -> AudioObjectID?) async throws -> Int {
    let capture = MicrophoneCapture(input: EngineAudioInput(device: device))
    try capture.start()
    do {
        let deadline = Date().addingTimeInterval(2)
        while capture.timings.firstChunk == nil && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    } catch {
        _ = capture.stop()
        throw error
    }
    return capture.stop().samples.count
}

/// Real devices only; needs `ZACK_INTEGRATION=1`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ZACK_INTEGRATION"] == "1"), .serialized)
struct EngineAudioInputHardwareTests {
    @Test(.enabled(if: mismatchingInputDevice() != nil))
    func deliversChunksFromDeviceWithOtherRate() async throws {
        let id = try #require(mismatchingInputDevice())
        let input = EngineAudioInput(device: { id })
        let counter = Counter()
        try input.start(onChunk: { _ in counter.increment() }, onEvent: { _ in })
        let deadline = Date().addingTimeInterval(2)
        while counter.value == 0 && Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        input.stop()
        #expect(counter.value > 0)
    }

    /// Setting a device makes the engine post one spurious configuration change; the recording must survive it.
    @Test func captureRecordsFromTheDefaultDevice() async throws {
        let samples = try await recordedSamples(device: { AudioDevices.defaultInputID() })
        #expect(samples > 0)
    }

    @Test(.enabled(if: mismatchingInputDevice() != nil))
    func captureRecordsFromADeviceWithOtherRate() async throws {
        let id = try #require(mismatchingInputDevice())
        let samples = try await recordedSamples(device: { id })
        #expect(samples > 0)
    }
}
