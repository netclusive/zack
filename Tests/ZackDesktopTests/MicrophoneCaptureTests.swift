import Foundation
import Testing
import ZackCore

@testable import ZackDesktop

struct MicrophoneCaptureTests {
    @Test func recordsChunksIntoOneClip() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        input.push([0.1, 0.2])
        input.push([0.3])
        #expect(capture.stop() == AudioClip(samples: [0.1, 0.2, 0.3]))
        #expect(input.stopCount == 1)
    }

    @Test func startDropsTheLastRecording() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        input.push([0.1])
        _ = capture.stop()
        try capture.start()
        input.push([0.2])
        #expect(capture.stop().samples == [0.2])
    }

    @Test func chunksAfterStopAreIgnored() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        _ = capture.stop()
        input.push([0.5])
        #expect(capture.stop().samples.isEmpty)
    }

    @Test func cancelDropsSamples() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        input.push(tone())
        capture.cancel()
        #expect(capture.stop().samples.isEmpty)
        #expect(capture.level == 0)
    }

    @Test func levelFollowsTheLatestChunk() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        input.push(tone(seconds: 0.1, amplitude: 0.5))
        #expect(capture.level > 0.7)
        input.push(Array(repeating: 0, count: 1_600))
        #expect(capture.level == 0)
    }

    @Test func meterScaleCoversFiftyDecibels() {
        #expect(MicrophoneCapture.meterLevel(rms: 1) == 1)
        #expect(MicrophoneCapture.meterLevel(rms: 0.003_162) < 0.001)
        #expect(MicrophoneCapture.meterLevel(rms: 0) == 0)
        #expect(abs(MicrophoneCapture.meterLevel(rms: 0.056_23) - 0.5) < 0.001)
    }

    @Test func timingsMeasureFirstChunkAndFirstSound() throws {
        let input = FakeAudioInput()
        let clock = ManualNow()
        let capture = MicrophoneCapture(input: input, now: { clock.now })
        try capture.start()
        clock.advance(by: .milliseconds(40))
        input.push(Array(repeating: 0, count: 1_600))
        clock.advance(by: .milliseconds(50))
        input.push(tone(seconds: 0.1))
        clock.advance(by: .milliseconds(100))
        input.push(tone(seconds: 0.1))
        #expect(capture.timings == .init(firstChunk: .milliseconds(40), firstSound: .milliseconds(90)))
    }

    @Test func failedStartLeavesTheCaptureStopped() {
        let input = FakeAudioInput()
        input.failStarts(with: .audioFormat)
        let capture = MicrophoneCapture(input: input)
        #expect(throws: ZackError.audioFormat) { try capture.start() }
        input.push([0.4])
        #expect(capture.stop().samples.isEmpty)
    }

    // Events are handled on the capture's control queue; the next `stop` runs after them, so it is a barrier.

    @Test func lostDeviceIsForwarded() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        let interrupted = Counter()
        try capture.start(onInterruption: { interrupted.increment() })
        input.emit(.deviceLost)
        _ = capture.stop()
        #expect(interrupted.value == 1)
    }

    @Test func formatChangeRestartsTheInputAndKeepsRecording() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        let interrupted = Counter()
        try capture.start(onInterruption: { interrupted.increment() })
        input.push([0.1])
        input.emit(.formatChanged)
        input.push([0.2])
        #expect(capture.stop().samples == [0.1, 0.2])
        #expect(input.startCount == 2)
        #expect(interrupted.value == 0)
    }

    @Test func failedRestartEndsTheRecording() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        let interrupted = Counter()
        try capture.start(onInterruption: { interrupted.increment() })
        input.failStarts(with: .audioFormat)
        input.emit(.formatChanged)
        _ = capture.stop()
        #expect(interrupted.value == 1)
    }

    @Test func eventsAfterStopAreIgnored() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        let interrupted = Counter()
        try capture.start(onInterruption: { interrupted.increment() })
        _ = capture.stop()
        input.emit(.deviceLost)
        input.emit(.formatChanged)
        _ = capture.stop()
        #expect(interrupted.value == 0)
        #expect(input.startCount == 1)
    }

    @Test func lateEventOfAnEarlierStartDoesNotHitTheNextRecording() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        _ = capture.stop()
        let interrupted = Counter()
        try capture.start(onInterruption: { interrupted.increment() })
        input.emit(.deviceLost, fromStart: 0)
        input.emit(.formatChanged, fromStart: 0)
        _ = capture.stop()
        #expect(interrupted.value == 0)
        #expect(input.startCount == 2)
    }

    @Test func inFlightChunkOfTheOldStartIsKeptAcrossARestart() async throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        input.push([0.1], fromStart: 0)
        input.emit(.formatChanged)
        #expect(await eventually { input.startCount == 2 })
        // The tap of the old start may still deliver a buffer after the input restarted.
        input.push([0.2], fromStart: 0)
        input.push([0.3])
        #expect(capture.stop().samples == [0.1, 0.2, 0.3])
    }

    @Test func lateChunkOfAnEarlierStartIsDropped() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        _ = capture.stop()
        try capture.start()
        input.push([0.9], fromStart: 0)
        input.push([0.2])
        #expect(capture.stop().samples == [0.2])
    }

    @Test func secondStopReturnsNothing() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        input.push([0.1])
        #expect(capture.stop().samples == [0.1])
        #expect(capture.stop().samples.isEmpty)
    }

    @Test func restartRefusedByTheInputEndsTheRecording() throws {
        let input = RefusingRestartInput()
        let capture = MicrophoneCapture(input: input)
        let interrupted = Counter()
        try capture.start(onInterruption: { interrupted.increment() })
        input.emit(.formatChanged)
        _ = capture.stop()
        #expect(interrupted.value == 1)
        #expect(input.restartCount == 1)
    }

    // `startInBackground` returns at once; the start runs on the control queue, before any call made after it.

    @Test func backgroundStartReturnsWhileTheInputStarts() {
        let input = FakeAudioInput()
        let gate = input.blockNextStart()
        let capture = MicrophoneCapture(input: input)
        capture.startInBackground(onFailure: { _ in })
        #expect(input.startCount == 0)
        gate.open()
        capture.waitForControl()
        #expect(!gate.timedOut)
        #expect(input.startCount == 1)
        input.push([0.1])
        #expect(capture.stop().samples == [0.1])
    }

    @Test func backgroundStartMeasuresFromTheCall() {
        let input = FakeAudioInput()
        let gate = input.blockNextStart()
        let clock = ManualNow()
        let capture = MicrophoneCapture(input: input, now: { clock.now })
        capture.startInBackground(onFailure: { _ in })
        clock.advance(by: .milliseconds(300))
        gate.open()
        capture.waitForControl()
        input.push(tone(seconds: 0.1))
        #expect(capture.timings == .init(firstChunk: .milliseconds(300), firstSound: .milliseconds(300)))
    }

    @Test func backgroundStartReportsAFailure() {
        let input = FakeAudioInput()
        input.failStarts(with: .audioFormat)
        let capture = MicrophoneCapture(input: input)
        let failure = TestValue<ZackError?>(nil)
        capture.startInBackground(onFailure: { failure.set($0 as? ZackError) })
        capture.waitForControl()
        #expect(failure.current == .audioFormat)
        #expect(!capture.isInputOpen)
        #expect(capture.stop().samples.isEmpty)
    }

    @Test func stopWaitsForABackgroundStart() {
        let input = FakeAudioInput()
        let gate = input.blockNextStart()
        input.deliverOnStart([0.2])
        let capture = MicrophoneCapture(input: input)
        capture.startInBackground(onFailure: { _ in })
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.05) { gate.open() }
        #expect(capture.stop().samples == [0.2])
        #expect(!gate.timedOut)
        #expect(input.stopCount == 1)
        #expect(!capture.isInputOpen)
    }

    @Test func backgroundCancelReturnsAndDropsAfterTheStart() {
        let input = FakeAudioInput()
        let gate = input.blockNextStart()
        input.deliverOnStart([0.2])
        let capture = MicrophoneCapture(input: input)
        capture.startInBackground(onFailure: { _ in })
        capture.cancelInBackground()
        #expect(input.startCount == 0)
        gate.open()
        capture.waitForControl()
        #expect(!gate.timedOut)
        #expect(input.startCount == 1)
        #expect(input.stopCount == 1)
        #expect(!capture.isInputOpen)
        #expect(capture.stop().samples.isEmpty)
    }

    @Test func startAfterABackgroundCancelRecords() {
        let input = FakeAudioInput()
        let gate = input.blockNextStart()
        let capture = MicrophoneCapture(input: input)
        capture.startInBackground(onFailure: { _ in })
        capture.cancelInBackground()
        capture.startInBackground(onFailure: { _ in })
        gate.open()
        capture.waitForControl()
        input.push([0.3])
        #expect(capture.stop().samples == [0.3])
    }

    /// "micstart" spans the blocking start of the input, for a hand check of how long a cold start blocks.
    @Test func backgroundColdStartIsMarkedWhileItBlocks() {
        let input = FakeAudioInput()
        let gate = input.blockNextStart()
        let signposts = Signposts(signposter: .disabled)
        let capture = MicrophoneCapture(input: input)
        capture.startInBackground(signposts: signposts, onFailure: { _ in })
        #expect(eventuallyBlocking { signposts.openMicrophoneStarts == 1 })
        gate.open()
        capture.waitForControl()
        #expect(signposts.openMicrophoneStarts == 0)
        #expect(signposts.endedMicrophoneStarts == 1)
    }

    @Test func failedBackgroundStartEndsItsMark() {
        let input = FakeAudioInput()
        input.failStarts(with: .audioFormat)
        let signposts = Signposts(signposter: .disabled)
        let capture = MicrophoneCapture(input: input)
        capture.startInBackground(signposts: signposts, onFailure: { _ in })
        capture.waitForControl()
        #expect(signposts.openMicrophoneStarts == 0)
        #expect(signposts.endedMicrophoneStarts == 1)
    }

    @Test func warmBackgroundStartIsNotMarked() throws {
        let input = FakeAudioInput()
        let signposts = Signposts(signposter: .disabled)
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        capture.startInBackground(signposts: signposts, onFailure: { _ in })
        capture.waitForControl()
        #expect(signposts.endedMicrophoneStarts == 0)
    }

    @Test func defaultInputNameIsNilOrNamed() {
        // Hardware dependent: a Mac without an input device returns nil, never an empty name.
        if let name = AudioDevices.defaultInputName() { #expect(!name.isEmpty) }
    }
}
