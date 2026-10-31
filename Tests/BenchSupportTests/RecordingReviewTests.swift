import Foundation
import Testing
import ZackCore

@testable import BenchSupport

private func tone(seconds: Double, amplitude: Float) -> AudioClip {
    let count = Int(seconds * 16_000)
    return AudioClip(samples: (0..<count).map { amplitude * sin(Float($0) * 0.1) })
}

@Test func silentRecordingIsFlagged() {
    #expect(RecordingReview.problem(for: tone(seconds: 1, amplitude: 0)) == .silent)
    #expect(RecordingReview.problem(for: AudioClip(samples: [])) == .tooShort)
}

@Test func shortRecordingIsFlagged() {
    #expect(RecordingReview.problem(for: tone(seconds: 0.1, amplitude: 0.5)) == .tooShort)
}

@Test func normalRecordingPasses() {
    #expect(RecordingReview.problem(for: tone(seconds: 1, amplitude: 0.5)) == nil)
}

@Test func problemsHaveGermanMessages() {
    #expect(RecordingReview.Problem.silent.message.contains("still"))
    #expect(RecordingReview.Problem.tooShort.message.contains("kurz"))
}
