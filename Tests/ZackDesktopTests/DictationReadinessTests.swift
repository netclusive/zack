import Synchronization
import Testing
import ZackCore

@testable import ZackDesktop

/// A value the controller reads at each use; the test changes it in between.
final class TestValue<Value: Sendable>: Sendable {
    private let value: Mutex<Value>

    init(_ value: Value) {
        self.value = Mutex(value)
    }

    var current: Value { value.withLock { $0 } }

    func set(_ newValue: Value) {
        value.withLock { $0 = newValue }
    }
}

/// "Mikrofon bereithalten" in the dictation flow, with the test clock for the two-minute window.
@MainActor
struct DictationReadinessTests {
    let input = FakeAudioInput()
    let clock = TestClock()
    let clipboard = FakeClipboard()
    let keystrokes: FakeKeystrokes
    let capture: MicrophoneCapture
    let transcriber = FakeTranscriber("Hallo Welt.")

    init() {
        keystrokes = FakeKeystrokes(clipboard: clipboard)
        capture = MicrophoneCapture(input: input)
    }

    func makeController(
        readiness: TestValue<MicrophoneReadiness>, modelReady: TestValue<Bool> = TestValue(true)
    ) -> DictationController<TestClock> {
        let inserter = Inserter(
            clipboard: clipboard, keystrokes: keystrokes, canPostKeystrokes: { true }, frontmostBundleID: { nil },
            sleep: { _ in })
        return DictationController(
            capture: capture, transcriber: transcriber, inserter: inserter, clock: clock,
            makeProcessor: { TextProcessor() }, modelReady: { modelReady.current }, microphoneAllowed: { true },
            readiness: { readiness.current })
    }

    /// Key down, pill shown, one second spoken, key up after one second; then waits until the result and
    /// window timers sleep.
    func dictate(_ controller: DictationController<TestClock>, timers: Int = 2) async {
        await controller.begin()
        // The microphone starts in the background; audio arrives once it runs.
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(await eventually { clock.sleeperCount == timers })
    }

    @Test func microphoneClosesTwoMinutesAfterADictation() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        #expect(capture.isInputOpen)
        #expect(input.stopCount == 0)
        clock.advance(by: .seconds(119))
        #expect(capture.isInputOpen)
        clock.advance(by: .seconds(1))
        #expect(await eventually { !capture.isInputOpen })
        #expect(input.stopCount == 1)
    }

    @Test func dictationInsideTheWindowReusesTheInputAndStartsTheWindowAgain() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        clock.advance(by: .seconds(100))
        await dictate(controller)
        #expect(input.startCount == 1)
        clock.advance(by: .seconds(110))
        #expect(capture.isInputOpen)
        clock.advance(by: .seconds(10))
        #expect(await eventually { !capture.isInputOpen })
    }

    /// The window starts again at key release, so the previous one cannot close the input while the engine is
    /// still recognizing, and the new one does not wait for the insertion.
    @Test func windowStartsAgainAtKeyReleaseNotAtInsertion() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        clock.advance(by: .seconds(110))
        await transcriber.holdNext()
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        clock.advance(by: .seconds(5))
        // Released at 116 s; the previous window would end at 121 s.
        let finishing = Task { await controller.finish() }
        #expect(await eventually { await transcriber.isHeld })
        clock.advance(by: .seconds(10))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(capture.isWarm)
        #expect(capture.isInputOpen)
        // Inserted at 126 s; the window still ends 120 s after the release.
        await transcriber.resume()
        await finishing.value
        #expect(await controller.state == .inserted(.pasted))
        #expect(await eventually { clock.sleeperCount == 2 })
        clock.advance(by: .seconds(109))
        #expect(capture.isInputOpen)
        clock.advance(by: .seconds(1))
        #expect(await eventually { !capture.isInputOpen })
    }

    @Test func preRollOfTheConfiguredLengthStartsTheClip() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        // Between dictations the warm input keeps only the last half second.
        input.push(tone(seconds: 0.8))
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        clock.advance(by: .seconds(1))
        await controller.finish()
        let duration = await transcriber.lastAudio?.duration ?? 0
        #expect(abs(duration - (1 + 0.5)) < 0.001, "\(duration)")
        #expect(MicrophoneReadiness.preRoll == .milliseconds(500))
    }

    @Test func offClosesTheMicrophoneRightAfterADictation() async {
        let controller = makeController(readiness: TestValue(.off))
        await dictate(controller, timers: 1)
        #expect(!capture.isInputOpen)
        #expect(input.stopCount == 1)
    }

    @Test func switchingToOffClosesAWarmMicrophoneAtOnce() async {
        let readiness = TestValue(MicrophoneReadiness.afterDictation)
        let controller = makeController(readiness: readiness)
        await dictate(controller)
        readiness.set(.off)
        await controller.applyReadiness()
        #expect(!capture.isInputOpen)
        #expect(await eventually { clock.sleeperCount == 1 })
    }

    @Test func alwaysNeverCloses() async {
        let controller = makeController(readiness: TestValue(.always))
        await controller.applyReadiness()
        #expect(capture.isInputOpen)
        await dictate(controller, timers: 1)
        clock.advance(by: .seconds(3_600))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(capture.isInputOpen)
        #expect(input.startCount == 1)
        #expect(input.stopCount == 0)
    }

    @Test func alwaysOpensOnlyOnceTheModelIsThere() async {
        let modelReady = TestValue(false)
        let controller = makeController(readiness: TestValue(.always), modelReady: modelReady)
        await controller.applyReadiness()
        #expect(input.startCount == 0)
        modelReady.set(true)
        await controller.applyReadiness()
        await controller.applyReadiness()
        #expect(input.startCount == 1)
        #expect(capture.isWarm)
    }

    @Test func windowEndingDuringADictationKeepsItAndStartsTheWindowAgain() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        clock.advance(by: .seconds(110))
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        clock.advance(by: .seconds(10))
        #expect(await eventually { !capture.isWarm })
        #expect(capture.isInputOpen)
        await controller.finish()
        #expect(await transcriber.lastAudio?.duration == 1)
        #expect(capture.isWarm)
        #expect(input.startCount == 1)
        #expect(await eventually { clock.sleeperCount == 2 })
        clock.advance(by: .seconds(120))
        #expect(await eventually { !capture.isInputOpen })
    }

    @Test func windowEndingDuringACancelledHoldClosesTheMicrophone() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        clock.advance(by: .seconds(110))
        await controller.begin()
        clock.advance(by: .seconds(10))
        #expect(await eventually { !capture.isWarm })
        await controller.cancel()
        #expect(!capture.isInputOpen)
    }

    @Test func shortHoldDoesNotStartTheWindowAgain() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        clock.advance(by: .seconds(100))
        await controller.begin()
        await controller.confirm()
        clock.advance(by: .milliseconds(200))
        await controller.finish()
        #expect(await controller.state == .idle)
        clock.advance(by: .milliseconds(19_800))
        #expect(await eventually { !capture.isInputOpen })
    }

    @Test func shortHoldEndsSilentlyDespiteThePreRoll() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        // Half a second of sound waits in the pre-roll; the hold itself is shorter than a dictation.
        input.push(tone(seconds: 0.8))
        await controller.begin()
        await controller.confirm()
        clock.advance(by: .milliseconds(200))
        await controller.finish()
        #expect(await controller.state == .idle)
        #expect(await transcriber.calls == 1)
        #expect(capture.isInputOpen)
    }

    @Test func cancelledTapDoesNotStartTheWindowAgain() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        clock.advance(by: .seconds(100))
        await controller.begin()
        await controller.cancel()
        clock.advance(by: .seconds(20))
        #expect(await eventually { !capture.isInputOpen })
    }

    @Test func cancelledTapOnAColdMicrophoneLeavesItClosed() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await controller.begin()
        await controller.cancel()
        #expect(!capture.isInputOpen)
        #expect(await eventually { clock.sleeperCount == 0 })
    }

    /// A lost device ends the recording with a hint; the ready input opens again (on the control queue, after
    /// `cancel` returned) and the window, started again, still closes it.
    @Test func disconnectDuringAReadyRecordingReopensTheInputUntilTheWindowEnds() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        clock.advance(by: .seconds(100))
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        input.emit(.deviceLost)
        #expect(await eventually { await controller.state == .failed(.microphoneDisconnected) })
        capture.waitForControl()
        #expect(input.startCount == 2)
        #expect(capture.isInputOpen)
        #expect(capture.isWarm)
        #expect(await transcriber.calls == 1)
        #expect(await eventually { clock.sleeperCount == 2 })
        // The first window would have ended at 121 s; the disconnect at 101 s started it again.
        clock.advance(by: .seconds(119))
        #expect(capture.isInputOpen)
        clock.advance(by: .seconds(1))
        #expect(await eventually { !capture.isInputOpen })
    }

    /// A disconnect inside the tap window counts like the tap: the window of the last dictation goes on.
    @Test func disconnectDuringATapKeepsTheWindow() async {
        let controller = makeController(readiness: TestValue(.afterDictation))
        await dictate(controller)
        clock.advance(by: .seconds(100))
        await controller.begin()
        capture.waitForControl()
        input.emit(.deviceLost)
        // The ready input opens again on the new device.
        #expect(await eventually { input.startCount == 2 })
        await controller.cancel()
        #expect(await controller.state == .idle)
        clock.advance(by: .seconds(20))
        #expect(await eventually { !capture.isInputOpen })
    }

    // Key actions during a cold start that still blocks: `cancel` and `stop` queue behind the start, so the input
    // ends up as the setting says.

    @Test func tapDuringABlockedColdStartLeavesTheMicrophoneClosed() async {
        let gate = input.blockNextStart()
        let controller = makeController(readiness: TestValue(.afterDictation))
        let log = StateLog(controller)
        await controller.begin()
        #expect(input.startCount == 0)
        let cancelling = Task { await controller.cancel() }
        #expect(await eventually(within: .milliseconds(500)) { log.all.last == .idle })
        gate.open()
        await cancelling.value
        capture.waitForControl()
        #expect(!gate.timedOut)
        #expect(input.startCount == 1)
        #expect(input.stopCount == 1)
        #expect(!capture.isInputOpen)
        #expect(!capture.isWarm)
        #expect(clock.sleeperCount == 0)
    }

    /// "Aus" while the setup window is open: the app applies the setting once a second. A cold input has nothing to
    /// release, so applying must not wait for a start that still blocks, or the pill would come late.
    @Test func applyingOffDuringABlockedColdStartDoesNotWaitForTheStart() async {
        let gate = input.blockNextStart()
        input.deliverOnStart(tone())
        let controller = makeController(readiness: TestValue(.off))
        await controller.begin()
        for _ in 0..<3 { await controller.applyReadiness() }
        await controller.confirm()
        // The pill is up while the engine is still starting.
        #expect(await controller.state == .recording(elapsed: .zero, level: 0))
        #expect(input.startCount == 0)
        gate.open()
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(!gate.timedOut)
        #expect(await controller.state == .inserted(.pasted))
        #expect(!capture.isInputOpen)
        #expect(!capture.isWarm)
    }

    @Test(arguments: [MicrophoneReadiness.off, .afterDictation])
    func releaseDuringABlockedColdStartLeavesTheMicrophoneAsSet(readiness: MicrophoneReadiness) async {
        let gate = input.blockNextStart()
        // A tap buffer that fires while the engine starts: the recording has audio once the start returns.
        input.deliverOnStart(tone())
        let controller = makeController(readiness: TestValue(readiness))
        await controller.begin()
        await controller.confirm()
        #expect(input.startCount == 0)
        clock.advance(by: .seconds(1))
        let finishing = Task { await controller.finish() }
        try? await Task.sleep(for: .milliseconds(50))
        gate.open()
        await finishing.value
        #expect(!gate.timedOut)
        #expect(await controller.state == .inserted(.pasted))
        #expect(capture.isInputOpen == (readiness != .off))
        #expect(capture.isWarm == (readiness != .off))
        guard readiness == .afterDictation else { return }
        #expect(await eventually { clock.sleeperCount == 2 })
        clock.advance(by: .seconds(120))
        #expect(await eventually { !capture.isInputOpen })
    }
}
