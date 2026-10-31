import Testing
import ZackCore

@testable import ZackDesktop

struct PreRollTests {
    @Test func keepsOnlyTheNewestSamples() {
        var preRoll = PreRoll(duration: .milliseconds(1), sampleRate: 4_000)
        #expect(preRoll.capacity == 4)
        preRoll.append([1, 2, 3])
        preRoll.append([4, 5, 6])
        #expect(preRoll.samples == [3, 4, 5, 6])
    }

    @Test func longChunkKeepsItsEnd() {
        var preRoll = PreRoll(duration: .milliseconds(1), sampleRate: 4_000)
        preRoll.append([1, 2, 3, 4, 5, 6, 7])
        #expect(preRoll.samples == [4, 5, 6, 7])
    }

    @Test func zeroLengthKeepsNothing() {
        var preRoll = PreRoll(duration: .zero)
        preRoll.append([1, 2, 3])
        #expect(preRoll.samples.isEmpty)
    }

    @Test func halfASecondAtSixteenKilohertz() {
        var preRoll = PreRoll(duration: MicrophoneReadiness.preRoll)
        #expect(preRoll.capacity == 8_000)
        preRoll.append(tone(seconds: 2))
        #expect(preRoll.duration == .milliseconds(500))
        preRoll.removeAll()
        #expect(preRoll.duration == .zero)
    }

    @Test func removeAllFreesTheStorage() {
        var preRoll = PreRoll(duration: .milliseconds(1), sampleRate: 4_000)
        preRoll.append([1, 2, 3])
        preRoll.removeAll()
        // No audio stays allocated after a release.
        #expect(preRoll.samples.capacity == 0)
    }
}

/// Warm mode with the fake audio source. Events and default-input changes are handled on the capture's control
/// queue; `waitForControl` (or the next `stop`) runs after them.
struct MicrophoneCaptureWarmTests {
    @Test func warmUpOpensTheInputOnce() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.warmUp(preRoll: .milliseconds(500))
        #expect(input.startCount == 1)
        #expect(capture.isWarm)
        #expect(capture.isInputOpen)
    }

    @Test func failedWarmUpStaysCold() {
        let input = FakeAudioInput()
        input.failStarts(with: .audioFormat)
        let capture = MicrophoneCapture(input: input)
        #expect(throws: ZackError.audioFormat) { try capture.warmUp(preRoll: .milliseconds(500)) }
        #expect(!capture.isWarm)
        #expect(!capture.isInputOpen)
    }

    @Test func recordingStartsWithThePreRollAndKeepsTheInputOpen() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        input.push(Array(repeating: 0.1, count: 6_000))
        input.push(Array(repeating: 0.2, count: 6_000))
        try capture.start()
        input.push([0.3])
        let clip = capture.stop()
        #expect(clip.samples.count == 8_001)
        #expect(clip.samples.prefix(2_000).allSatisfy { $0 == 0.1 })
        #expect(clip.samples.dropFirst(2_000).prefix(6_000).allSatisfy { $0 == 0.2 })
        #expect(clip.samples.last == 0.3)
        #expect(input.startCount == 1)
        #expect(input.stopCount == 0)
    }

    @Test func idleAudioIsNeverKeptBeyondThePreRoll() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        input.push(tone(seconds: 3))
        try capture.start()
        #expect(capture.stop().duration == 0.5)
        // After a recording the pre-roll starts empty again.
        try capture.start()
        #expect(capture.stop().samples.isEmpty)
    }

    @Test func warmTimingsWithSoundInThePreRoll() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        input.push(tone(seconds: 0.3))
        try capture.start()
        #expect(capture.timings == .init(firstChunk: .zero, firstSound: .zero, preRoll: .milliseconds(300), warm: true))
    }

    @Test func warmTimingsWithASilentPreRollMeasureTheFirstSound() throws {
        let input = FakeAudioInput()
        let clock = ManualNow()
        let capture = MicrophoneCapture(input: input, now: { clock.now })
        try capture.warmUp(preRoll: .milliseconds(500))
        input.push(Array(repeating: 0, count: 8_000))
        try capture.start()
        clock.advance(by: .milliseconds(90))
        input.push(tone(seconds: 0.1))
        #expect(
            capture.timings
                == .init(firstChunk: .zero, firstSound: .milliseconds(90), preRoll: .milliseconds(500), warm: true))
    }

    @Test func warmStartWithAnEmptyPreRollIsMarkedWarm() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start()
        #expect(capture.timings == .init(warm: true))
        _ = capture.stop()
        #expect(capture.timings.warm)
    }

    @Test func coldStartIsNotMarkedWarm() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        input.push(tone(seconds: 0.1))
        #expect(!capture.timings.warm)
    }

    @Test func releaseClosesTheIdleInputAndDropsThePreRoll() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        input.push(tone(seconds: 0.5))
        capture.release()
        #expect(input.stopCount == 1)
        #expect(!capture.isWarm)
        input.push(tone(seconds: 0.5))
        try capture.start()
        #expect(input.startCount == 2)
        #expect(capture.stop().samples.isEmpty)
        #expect(input.stopCount == 2)
    }

    @Test func releaseDuringARecordingClosesWhenItEnds() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start()
        input.push([0.1])
        capture.release()
        #expect(input.stopCount == 0)
        input.push([0.2])
        #expect(capture.stop().samples == [0.1, 0.2])
        #expect(input.stopCount == 1)
    }

    @Test func cancelKeepsTheWarmInputOpen() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start()
        input.push(tone(seconds: 0.2))
        capture.cancel()
        #expect(input.stopCount == 0)
        #expect(capture.isInputOpen)
    }

    @Test(arguments: [AudioInputEvent.deviceLost, .formatChanged])
    func idleWarmInputOpensAgainAfterAnEvent(event: AudioInputEvent) throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        input.emit(event)
        capture.waitForControl()
        #expect(input.stopCount == 1)
        #expect(input.startCount == 2)
        // A late buffer of the old device stays out; the new device fills the pre-roll.
        input.push([0.9], fromStart: 0)
        input.push([0.1])
        try capture.start()
        #expect(capture.stop().samples == [0.1])
    }

    @Test func idleWarmInputFollowsADefaultInputChange() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        capture.inputChanged()
        capture.waitForControl()
        #expect(input.startCount == 2)
        #expect(capture.isInputOpen)
    }

    @Test func warmInputThatCouldNotOpenAgainTriesOnTheNextDefaultInput() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        input.failStarts(with: .audioFormat)
        input.emit(.deviceLost)
        capture.waitForControl()
        #expect(!capture.isInputOpen)
        #expect(capture.isWarm)
        input.allowStarts()
        capture.inputChanged()
        capture.waitForControl()
        #expect(capture.isInputOpen)
        #expect(input.startCount == 2)
    }

    @Test func defaultInputChangeDuringARecordingWaitsForItsEnd() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start()
        capture.inputChanged()
        capture.waitForControl()
        #expect(input.startCount == 1)
        input.push([0.4])
        #expect(capture.stop().samples == [0.4])
        capture.waitForControl()
        #expect(input.startCount == 2)
        #expect(input.stopCount == 1)
    }

    @Test func lostDeviceStillEndsAWarmRecordingAndTheInputOpensAgainAfterwards() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        let interrupted = Counter()
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start(onInterruption: { interrupted.increment() })
        input.emit(.deviceLost)
        capture.waitForControl()
        #expect(interrupted.value == 1)
        // The controller cancels from another task; the warm input then opens on the new default device.
        capture.cancel()
        capture.waitForControl()
        #expect(input.startCount == 2)
        #expect(capture.isInputOpen)
    }

    @Test func restartDuringAWarmRecordingStillRefusesADeviceSwitch() throws {
        let input = RefusingRestartInput()
        let capture = MicrophoneCapture(input: input)
        let interrupted = Counter()
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start(onInterruption: { interrupted.increment() })
        input.emit(.formatChanged)
        capture.waitForControl()
        #expect(interrupted.value == 1)
        #expect(input.restartCount == 1)
    }

    @Test(arguments: [true, false])
    func refusedRestartDuringAWarmRecordingOpensTheInputAgainAfterwards(stopInsteadOfCancel: Bool) throws {
        let input = RefusingRestartInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start()
        input.emit(.formatChanged)
        capture.waitForControl()
        #expect(input.startCount == 1)
        if stopInsteadOfCancel { _ = capture.stop() } else { capture.cancel() }
        capture.waitForControl()
        // The input moves to the new default device once the recording is over.
        #expect(input.startCount == 2)
        #expect(capture.isInputOpen)
    }

    @Test func stopReturnsBeforeTheInputOpensAgain() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start()
        input.push([0.1])
        capture.inputChanged()
        capture.waitForControl()
        // The new device's start blocks until the test lets it go; `stop` must not wait for it.
        let gate = input.blockNextStart()
        let clip = capture.stop()
        #expect(clip.samples == [0.1])
        gate.open()
        capture.waitForControl()
        #expect(!gate.timedOut)
        #expect(input.startCount == 2)
        #expect(capture.isInputOpen)
    }

    @Test func chunkDeliveredWhileAWarmUpStartsLandsInThePreRoll() throws {
        let input = FakeAudioInput()
        input.deliverOnStart([0.1, 0.2])
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start()
        #expect(capture.stop().samples == [0.1, 0.2])
    }

    @Test func chunkDeliveredWhileAReopenStartsLandsInThePreRoll() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        input.deliverOnStart([0.3])
        capture.inputChanged()
        capture.waitForControl()
        try capture.start()
        #expect(capture.stop().samples == [0.3])
    }

    @Test func chunkDeliveredWhileAColdStartRunsIsRecorded() throws {
        let input = FakeAudioInput()
        input.deliverOnStart([0.4])
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        #expect(capture.stop().samples == [0.4])
    }

    @Test func failedStartsLeaveTheInputClosed() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        input.failStarts(with: .audioFormat)
        #expect(throws: ZackError.audioFormat) { try capture.start() }
        #expect(!capture.isInputOpen)
        #expect(throws: ZackError.audioFormat) { try capture.warmUp(preRoll: .milliseconds(500)) }
        #expect(!capture.isInputOpen)
    }

    @Test func idleAudioNeverMovesTheLevel() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        input.push(tone(seconds: 0.5, amplitude: 0.5))
        #expect(capture.level == 0)
    }

    @Test func cancelledRecordingLeavesAnEmptyPreRoll() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start()
        input.push(tone(seconds: 0.2))
        capture.cancel()
        try capture.start()
        #expect(capture.stop().samples.isEmpty)
    }

    @Test func nextStartOpensColdAfterAFailedReopen() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        input.failStarts(with: .audioFormat)
        input.emit(.deviceLost)
        capture.waitForControl()
        input.allowStarts()
        try capture.start()
        #expect(input.startCount == 2)
        input.push([0.1])
        #expect(capture.stop().samples == [0.1])
        // Still warm: the input opened by the recording stays open.
        #expect(capture.isInputOpen)
        #expect(input.stopCount == 1)
    }

    @Test func lateBufferFromBeforeAReleaseNeverReachesTheNextWarmUp() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        input.push(tone(seconds: 0.5))
        capture.release()
        try capture.warmUp(preRoll: .milliseconds(500))
        input.push(tone(seconds: 0.1), fromStart: 0)
        try capture.start()
        #expect(capture.stop().samples.isEmpty)
        #expect(input.startCount == 2)
    }

    @Test func formatChangeDuringAWarmRecordingKeepsItAndTheInputOpen() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        let interrupted = Counter()
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start(onInterruption: { interrupted.increment() })
        input.push([0.1])
        input.emit(.formatChanged)
        capture.waitForControl()
        input.push([0.2])
        #expect(capture.stop().samples == [0.1, 0.2])
        #expect(interrupted.value == 0)
        #expect(input.startCount == 2)
        #expect(input.stopCount == 1)
        #expect(capture.isInputOpen)
    }

    @Test func defaultInputChangeDuringAColdRecordingThatEndsWarmMovesTheInput() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        capture.inputChanged()
        capture.waitForControl()
        // A finished dictation keeps the input with `warmUp` before `stop`.
        try capture.warmUp(preRoll: .milliseconds(500))
        _ = capture.stop()
        capture.waitForControl()
        #expect(input.startCount == 2)
        #expect(input.stopCount == 1)
        #expect(capture.isInputOpen)
    }

    @Test func defaultInputChangeSurvivesAReleaseAndWarmUpDuringTheRecording() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.warmUp(preRoll: .milliseconds(500))
        try capture.start()
        capture.inputChanged()
        capture.waitForControl()
        // The window ends during the dictation, which then finishes and keeps the input.
        capture.release()
        try capture.warmUp(preRoll: .milliseconds(500))
        _ = capture.stop()
        capture.waitForControl()
        #expect(input.startCount == 2)
        #expect(input.stopCount == 1)
        #expect(capture.isInputOpen)
    }

    @Test func coldStopKeepsABufferThatArrivesWhileTheInputStops() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        try capture.start()
        input.push([0.1])
        input.deliverOnStop([0.2])
        #expect(capture.stop().samples == [0.1, 0.2])
    }

    @Test func coldCaptureIgnoresDefaultInputChanges() throws {
        let input = FakeAudioInput()
        let capture = MicrophoneCapture(input: input)
        capture.inputChanged()
        try capture.start()
        capture.inputChanged()
        capture.waitForControl()
        _ = capture.stop()
        #expect(input.startCount == 1)
        #expect(input.stopCount == 1)
    }
}
