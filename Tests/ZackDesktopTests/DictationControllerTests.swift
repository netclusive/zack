import Synchronization
import Testing
import ZackCore

@testable import ZackDesktop

extension DictationState {
    /// The states a pill appears for; `PillContent` decides this in the app.
    var showsPill: Bool {
        switch self {
        case .idle, .listening: false
        default: true
        }
    }
}

/// Only the engines are replaced: the real `Inserter` works on a fake
/// clipboard and fake keystrokes, the real `MicrophoneCapture` on a fake audio source.

/// Collects every published state.
final class StateLog: Sendable {
    private let states = Mutex<[DictationState]>([])

    init<C>(_ controller: DictationController<C>) {
        let stream = controller.states
        Task { [weak self] in
            for await state in stream { self?.record(state) }
        }
    }

    private func record(_ state: DictationState) {
        states.withLock { $0.append(state) }
    }

    var all: [DictationState] { states.withLock { $0 } }
}

@MainActor
struct DictationControllerTests {
    let input = FakeAudioInput()
    let clock = TestClock()
    let clipboard = FakeClipboard()
    let keystrokes: FakeKeystrokes
    let capture: MicrophoneCapture
    /// Real latency marks that write nothing to the log `scripts/latency.sh` reads.
    let signposts = Signposts(signposter: .disabled)

    init() {
        keystrokes = FakeKeystrokes(clipboard: clipboard)
        capture = MicrophoneCapture(input: input)
    }

    func makeController(
        transcriber: FakeTranscriber = FakeTranscriber("Hallo Welt."), cleaner: (any Cleaner)? = nil,
        modelReady: Bool = true, microphone: Bool = true, accessibility: Bool = true,
        language: @escaping @Sendable () -> DictationLanguage = { .german }
    ) -> DictationController<TestClock> {
        let inserter = Inserter(
            clipboard: clipboard, keystrokes: keystrokes, canPostKeystrokes: { accessibility }, sleep: { _ in })
        return DictationController(
            capture: capture, transcriber: transcriber, inserter: inserter, clock: clock,
            makeProcessor: { TextProcessor(vocabulary: Vocabulary(terms: ["GitHub"]), cleaner: cleaner) },
            modelReady: { modelReady }, microphoneAllowed: { microphone }, signposts: signposts,
            language: language)
    }

    /// Key down, pill shown, `samples` spoken, key up after one second. Latency marks begin as in the app: at key
    /// down and at every key release.
    func dictate(_ controller: DictationController<TestClock>, _ samples: [Float]) async {
        signposts.beginPill()
        await controller.begin()
        // The microphone starts in the background; audio arrives once it runs.
        capture.waitForControl()
        await controller.confirm()
        input.push(samples)
        clock.advance(by: .seconds(1))
        signposts.beginInsert()
        await controller.finish()
    }

    /// Runs key actions one after the other, as the app's hotkey stream does.
    func hotkeyStream(
        _ controller: DictationController<TestClock>
    ) -> (keys: AsyncStream<HotkeyAction>.Continuation, done: Task<Void, Never>) {
        let (stream, keys) = AsyncStream.makeStream(of: HotkeyAction.self)
        let done = Task {
            for await action in stream {
                switch action {
                case .begin: await controller.begin()
                case .confirm: await controller.confirm()
                case .finish: await controller.finish()
                case .cancel: await controller.cancel()
                }
            }
        }
        return (keys, done)
    }

    @Test func holdSpeakReleaseInsertsTheText() async {
        let transcriber = FakeTranscriber("Hallo Welt.")
        let controller = makeController(transcriber: transcriber)
        await controller.begin()
        capture.waitForControl()
        #expect(await controller.state == .listening)
        await controller.confirm()
        #expect(await controller.state == .recording(elapsed: .zero, level: 0))
        input.push(tone())
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(await controller.state == .inserted(.pasted))
        #expect(keystrokes.pasted == ["Hallo Welt."])
        #expect(await controller.lastText == "Hallo Welt.")
        #expect(await transcriber.lastHints == ["GitHub"])
    }

    @Test func silenceInsertsNothing() async {
        let transcriber = FakeTranscriber("Vielen Dank.")
        let controller = makeController(transcriber: transcriber)
        await dictate(controller, Array(repeating: 0, count: 16_000))
        #expect(await controller.state == .failed(.nothingHeard))
        #expect(await transcriber.calls == 0)
        #expect(keystrokes.pasted.isEmpty)
    }

    /// Held long enough, but the microphone delivered too little (as after a slow cold start).
    @Test func clipUnderMinimumIsNothingHeard() async {
        let controller = makeController()
        await dictate(controller, tone(seconds: 0.2))
        #expect(await controller.state == .failed(.nothingHeard))
    }

    @Test func shortHoldEndsWithoutAMessage() async {
        let transcriber = FakeTranscriber("Hallo")
        let controller = makeController(transcriber: transcriber)
        let log = StateLog(controller)
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone(seconds: 0.2))
        clock.advance(by: .milliseconds(250))
        await controller.finish()
        #expect(await controller.state == .idle)
        #expect(await eventually { log.all.last == .idle })
        #expect(!log.all.contains(.failed(.nothingHeard)))
        #expect(await transcriber.calls == 0)
        #expect(keystrokes.pasted.isEmpty)
        #expect(input.stopCount == 1)
    }

    @Test func holdOfTheMinimumDurationIsADictation() async {
        let controller = makeController()
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        clock.advance(by: .milliseconds(300))
        await controller.finish()
        #expect(await controller.state == .inserted(.pasted))
    }

    @Test func cancelDropsTheAudio() async {
        let transcriber = FakeTranscriber("Hallo")
        let controller = makeController(transcriber: transcriber)
        await controller.begin()
        capture.waitForControl()
        input.push(tone())
        await controller.cancel()
        #expect(await controller.state == .idle)
        #expect(input.stopCount == 1)
        await controller.finish()
        #expect(await transcriber.calls == 0)
    }

    @Test func failedRecognitionKeepsTheAudioForRetry() async {
        let transcriber = FakeTranscriber("")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber)
        await dictate(controller, tone())
        #expect(await controller.state == .failed(.recognitionFailed))
        #expect(await controller.canRetry)
        await transcriber.respond(with: .success("Zweiter Versuch."))
        await controller.retry()
        #expect(await controller.state == .inserted(.pasted))
        #expect(keystrokes.pasted == ["Zweiter Versuch."])
        #expect(await !controller.canRetry)
    }

    @Test func nextDictationDropsTheRetryAudio() async {
        let transcriber = FakeTranscriber("")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber)
        await dictate(controller, tone())
        // Even a silent dictation replaces the kept audio.
        await dictate(controller, Array(repeating: 0, count: 16_000))
        #expect(await controller.state == .failed(.nothingHeard))
        #expect(await !controller.canRetry)
    }

    @Test func tapAndShortHoldKeepTheRetryAudio() async {
        let transcriber = FakeTranscriber("")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber)
        await dictate(controller, tone())
        await controller.begin()
        await controller.cancel()
        await controller.begin()
        await controller.confirm()
        clock.advance(by: .milliseconds(200))
        await controller.finish()
        #expect(await controller.state == .idle)
        #expect(await controller.canRetry)
        await transcriber.respond(with: .success("Zweiter Versuch."))
        await controller.retry()
        #expect(keystrokes.pasted == ["Zweiter Versuch."])
    }

    @Test func recordingEndsAtThreeMinutes() async {
        let transcriber = FakeTranscriber("Langes Diktat.")
        let controller = makeController(transcriber: transcriber)
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: .seconds(181))
        #expect(await eventually { await controller.state == .inserted(.pasted) })
        #expect(await transcriber.calls == 1)
    }

    /// The limit hands over to a new task; if that task runs late, it must not end the next dictation.
    @Test func lateLimitOfAnEarlierDictationDoesNotEndTheNextOne() async {
        let controller = makeController()
        // Session 1.
        await dictate(controller, tone())
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        await controller.finishAtLimit(session: 1)
        #expect(await controller.state == .recording(elapsed: .zero, level: 0))
        input.push(tone())
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(keystrokes.pasted == ["Hallo Welt.", "Hallo Welt."])
    }

    /// From 2:45 the pill counts down while the recording goes on; it ends at exactly 3:00.
    @Test func recordingGoesOnPastTheHintAndEndsAtTheLimit() async {
        #expect(DictationLimits.hint == .seconds(165))
        #expect(DictationLimits.maximum == .seconds(180))
        let transcriber = FakeTranscriber("Langes Diktat.")
        let controller = makeController(transcriber: transcriber)
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: DictationLimits.hint)
        #expect(
            await eventually {
                if case .recording(let elapsed, _) = await controller.state { return elapsed == DictationLimits.hint }
                return false
            })
        #expect(await transcriber.calls == 0)
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: DictationLimits.maximum - DictationLimits.hint)
        #expect(await eventually { await controller.state == .inserted(.pasted) })
        #expect(await transcriber.calls == 1)
    }

    @Test func recordingStateCarriesTimeAndLevel() async {
        let controller = makeController()
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone(seconds: 0.1, amplitude: 0.5))
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: .seconds(2))
        #expect(
            await eventually {
                if case .recording(let elapsed, let level) = await controller.state {
                    return elapsed == .seconds(2) && level > 0.7
                }
                return false
            })
    }

    @Test(arguments: [true, false])
    func aiToggleDecidesAboutTheCleaner(aiOn: Bool) async {
        let controller = makeController(
            transcriber: FakeTranscriber("Das Treffen ist am Dienstag, nein, am Mittwoch."),
            cleaner: aiOn ? StubCleaner(output: "Das Treffen ist am Mittwoch.") : nil)
        let log = StateLog(controller)
        await dictate(controller, tone())
        let expected = aiOn ? "Das Treffen ist am Mittwoch." : "Das Treffen ist am Dienstag, nein, am Mittwoch."
        #expect(keystrokes.pasted == [expected])
        #expect(await eventually { log.all.last == .inserted(.pasted) })
        #expect(log.all.contains(.cleaning) == aiOn)
    }

    /// An implausible cleaner output falls back to the rule text.
    @Test func implausibleCleanerOutputInsertsTheRuleText() async {
        let controller = makeController(
            transcriber: FakeTranscriber("Das Treffen ist am Dienstag, nein, am Mittwoch."),
            cleaner: StubCleaner(output: "Gerne, ich habe den Termin eingetragen."))
        await dictate(controller, tone())
        #expect(await controller.state == .inserted(.pasted))
        #expect(keystrokes.pasted == ["Das Treffen ist am Dienstag, nein, am Mittwoch."])
    }

    /// Key down and the pill shown, with the microphone running.
    func startRecording(_ controller: DictationController<TestClock>) async {
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
    }

    /// The ticker and the prewarm loop both sleep on the clock.
    func prewarmLoopIsWaiting() async -> Bool {
        await eventually { clock.sleeperCount == 2 }
    }

    /// No further call is expected, so there is nothing to wait for; give a wrongly running loop time to show.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    @Test func prewarmRunsAtOnceAndEveryThreeSecondsWhileRecording() async {
        let cleaner = RecordingCleaner()
        let controller = makeController(
            transcriber: FakeTranscriber("Das Treffen ist am Dienstag, nein, am Mittwoch."), cleaner: cleaner)
        await startRecording(controller)
        #expect(await eventually { cleaner.prewarms.count == 1 })
        #expect(cleaner.prewarms[0] == .init(mode: .prose, vocabulary: ["GitHub"]))
        #expect(await prewarmLoopIsWaiting())
        clock.advance(by: .seconds(3))
        #expect(await eventually { cleaner.prewarms.count == 2 })
        #expect(await prewarmLoopIsWaiting())
        clock.advance(by: .seconds(3))
        #expect(await eventually { cleaner.prewarms.count == 3 })
        input.push(tone())
        await controller.finish()
        let count = cleaner.prewarms.count
        clock.advance(by: .seconds(10))
        await settle()
        #expect(cleaner.prewarms.count == count)
    }

    @Test(arguments: [true, false])
    func aTapNeverPrewarms(cancelled: Bool) async {
        let cleaner = RecordingCleaner()
        let controller = makeController(cleaner: cleaner)
        await controller.begin()
        capture.waitForControl()
        if cancelled { await controller.cancel() } else { await controller.finish() }
        clock.advance(by: .seconds(10))
        await settle()
        #expect(cleaner.prewarms.isEmpty)
    }

    @Test func controllerReadsLanguageOncePerDictation() async {
        let cleaner = RecordingCleaner()
        let calls = Mutex(0)
        let controller = makeController(
            transcriber: FakeTranscriber("The meeting is on Tuesday, scratch that, on Wednesday."), cleaner: cleaner,
            language: {
                calls.withLock {
                    $0 += 1
                    return $0 == 1 ? .english : .german
                }
            })
        await startRecording(controller)
        #expect(await eventually { cleaner.prewarms.count == 1 })
        clock.advance(by: .seconds(3))
        #expect(await eventually { cleaner.prewarms.count == 2 })
        input.push(tone())
        await controller.finish()
        #expect(cleaner.cleanLanguages == [.english])
        #expect(Set(cleaner.prewarmLanguages) == [.english])
        #expect(calls.withLock { $0 } == 1)
    }

    @Test func withoutACleanerNothingIsPrewarmed() async {
        let controller = makeController(cleaner: nil)
        await startRecording(controller)
        clock.advance(by: .seconds(4))
        input.push(tone())
        await controller.finish()
        #expect(await controller.state == .inserted(.pasted))
    }

    @Test func cancelAfterConfirmStopsPrewarmingAndDiscards() async {
        let cleaner = RecordingCleaner()
        let controller = makeController(cleaner: cleaner)
        await startRecording(controller)
        #expect(await eventually { cleaner.prewarms.count == 1 })
        await controller.cancel()
        #expect(cleaner.discards == 1)
        clock.advance(by: .seconds(10))
        await settle()
        #expect(cleaner.prewarms.count == 1)
        #expect(cleaner.discards == 1)
    }

    @Test func aShortHoldDiscards() async {
        let cleaner = RecordingCleaner()
        let controller = makeController(cleaner: cleaner)
        await startRecording(controller)
        #expect(await eventually { cleaner.prewarms.count == 1 })
        clock.advance(by: .milliseconds(200))
        await controller.finish()
        #expect(await controller.state == .idle)
        #expect(cleaner.discards == 1)
    }

    @Test func silenceDiscards() async {
        let cleaner = RecordingCleaner()
        let controller = makeController(cleaner: cleaner)
        await startRecording(controller)
        #expect(await eventually { cleaner.prewarms.count == 1 })
        input.push(Array(repeating: 0, count: 16_000))
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(await controller.state == .failed(.nothingHeard))
        #expect(cleaner.discards == 1)
        #expect(cleaner.cleans == 0)
    }

    @Test func aTextWithoutASignalWordDiscardsTheSession() async {
        let cleaner = RecordingCleaner()
        let controller = makeController(transcriber: FakeTranscriber("Hallo Welt."), cleaner: cleaner)
        await startRecording(controller)
        #expect(await eventually { cleaner.prewarms.count == 1 })
        input.push(tone())
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(cleaner.cleans == 0)
        #expect(cleaner.discards == 1)
    }

    @Test func aSignalWordCleansOnceAndNothingIsPrewarmedAfterwards() async {
        let cleaner = RecordingCleaner()
        let controller = makeController(
            transcriber: FakeTranscriber("Das Treffen ist am Dienstag, nein, am Mittwoch."), cleaner: cleaner)
        await startRecording(controller)
        #expect(await eventually { cleaner.prewarms.count == 1 })
        input.push(tone())
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(cleaner.cleans == 1)
        let count = cleaner.prewarms.count
        clock.advance(by: .seconds(10))
        await settle()
        #expect(cleaner.prewarms.count == count)
    }

    /// `makeProcessor` is still running when the key goes up: no prewarm may follow the cancel.
    @Test func cancelBeforeTheProcessorIsThereNeverPrewarms() async {
        let cleaner = RecordingCleaner()
        let gate = ProcessorGate()
        let inserter = Inserter(
            clipboard: clipboard, keystrokes: keystrokes, canPostKeystrokes: { true }, sleep: { _ in })
        let controller = DictationController(
            capture: capture, transcriber: FakeTranscriber("Hallo Welt."), inserter: inserter, clock: clock,
            makeProcessor: {
                await gate.wait()
                return TextProcessor(cleaner: cleaner)
            }, modelReady: { true }, microphoneAllowed: { true }, signposts: signposts)
        await startRecording(controller)
        await controller.cancel()
        await gate.release()
        clock.advance(by: .seconds(10))
        await settle()
        #expect(cleaner.prewarms.isEmpty)
    }

    @Test func missingModelShowsAHintInsteadOfRecording() async {
        let controller = makeController(modelReady: false)
        await controller.begin()
        #expect(input.startCount == 0)
        #expect(await controller.state == .listening)
        await controller.confirm()
        #expect(await controller.state == .failed(.modelMissing))
    }

    @Test func quickTapWithMissingModelShowsNothing() async {
        let controller = makeController(modelReady: false)
        await controller.begin()
        await controller.cancel()
        #expect(await controller.state == .idle)
    }

    @Test func deniedMicrophoneShowsAHint() async {
        let controller = makeController(microphone: false)
        await controller.begin()
        await controller.confirm()
        #expect(await controller.state == .failed(.microphoneDenied))
        #expect(input.startCount == 0)
    }

    @Test func microphoneStartFailureShowsAHint() async {
        input.failStarts(with: .audioFormat)
        let controller = makeController()
        await controller.begin()
        await controller.confirm()
        // The failure arrives from the background start, before or after the pill appeared.
        #expect(await eventually { await controller.state == .failed(.microphoneUnavailable) })
    }

    @Test func disconnectAbortsTheRecording() async {
        let transcriber = FakeTranscriber("Hallo")
        let controller = makeController(transcriber: transcriber)
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        input.emit(.deviceLost)
        #expect(await eventually { await controller.state == .failed(.microphoneDisconnected) })
        await controller.finish()
        #expect(await transcriber.calls == 0)
    }

    /// Inside the tap window nothing has appeared yet: a tap stays silent even if the microphone went away.
    @Test func disconnectDuringATapShowsNothing() async {
        let controller = makeController()
        let log = StateLog(controller)
        await controller.begin()
        capture.waitForControl()
        input.emit(.deviceLost)
        #expect(await eventually { input.stopCount == 1 })
        await controller.cancel()
        #expect(await controller.state == .idle)
        #expect(await eventually { log.all.last == .idle })
        #expect(!log.all.contains { $0.showsPill })
    }

    @Test func holdPastTheTapWindowShowsTheEarlierDisconnect() async {
        let transcriber = FakeTranscriber("Hallo")
        let controller = makeController(transcriber: transcriber)
        await controller.begin()
        capture.waitForControl()
        input.emit(.deviceLost)
        #expect(await eventually { input.stopCount == 1 })
        #expect(await controller.state == .listening)
        await controller.confirm()
        #expect(await controller.state == .failed(.microphoneDisconnected))
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(await controller.state == .failed(.microphoneDisconnected))
        #expect(await transcriber.calls == 0)
    }

    @Test func resultDisappearsAfterADelay() async {
        let controller = makeController()
        await dictate(controller, tone())
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: .milliseconds(1_200))
        #expect(await eventually { await controller.state == .idle })
    }

    @Test func withoutAccessibilityTheTextIsOnTheClipboard() async {
        let controller = makeController(accessibility: false)
        await dictate(controller, tone())
        #expect(await controller.state == .inserted(.clipboardOnly))
        #expect(keystrokes.pasted.isEmpty)
        #expect(clipboard.text == "Hallo Welt.")
    }

    @Test func formatChangeKeepsTheRecording() async {
        let controller = makeController()
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone(seconds: 0.5))
        input.emit(.formatChanged)
        input.push(tone(seconds: 0.5))
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(await controller.state == .inserted(.pasted))
        #expect(input.startCount == 2)
    }

    @Test func secondKeyDownWhileRecordingIsIgnored() async {
        let controller = makeController()
        await controller.begin()
        await controller.begin()
        capture.waitForControl()
        #expect(input.startCount == 1)
    }

    // A cold start blocks while the audio engine starts. The controller must not wait for it: the pill appears on
    // time and key actions are handled when they happen.

    @Test func pillAppearsWhileTheMicrophoneIsStillStarting() async {
        let gate = input.blockNextStart()
        let controller = makeController()
        await controller.begin()
        await controller.confirm()
        #expect(await controller.state == .recording(elapsed: .zero, level: 0))
        #expect(await !controller.canRetry)
        #expect(input.startCount == 0)
        gate.open()
        capture.waitForControl()
        #expect(!gate.timedOut)
        input.push(tone())
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(await controller.state == .inserted(.pasted))
    }

    /// Key down at 0, released at 0.2 s, the engine start returns at 0.4 s: the hold counts up to the release.
    @Test func shortHoldDuringASlowStartEndsSilently() async {
        let gate = input.blockNextStart()
        let controller = makeController()
        let log = StateLog(controller)
        let (keys, done) = hotkeyStream(controller)
        keys.yield(.begin)
        keys.yield(.confirm)
        #expect(await eventually { log.all.contains(.listening) })
        clock.advance(by: .milliseconds(200))
        keys.yield(.finish)
        // Handled at once, before the start returns.
        #expect(await eventually(within: .milliseconds(500)) { log.all.last == .idle })
        clock.advance(by: .milliseconds(200))
        gate.open()
        keys.finish()
        await done.value
        #expect(!gate.timedOut)
        #expect(await controller.state == .idle)
        #expect(!log.all.contains(.failed(.nothingHeard)))
        capture.waitForControl()
        #expect(!capture.isInputOpen)
    }

    @Test func startFailingAfterThePillAppearedShowsAHint() async {
        let gate = input.blockNextStart()
        input.failStarts(with: .audioFormat)
        let controller = makeController()
        await controller.begin()
        await controller.confirm()
        #expect(await controller.state == .recording(elapsed: .zero, level: 0))
        gate.open()
        #expect(await eventually { await controller.state == .failed(.microphoneUnavailable) })
        #expect(!gate.timedOut)
    }

    /// The start fails while the release waits for it: the hint names the microphone, not "Nichts gehört".
    @Test func startFailingDuringTheReleaseShowsAHint() async {
        let gate = input.blockNextStart()
        input.failStarts(with: .audioFormat)
        let controller = makeController()
        await controller.begin()
        await controller.confirm()
        clock.advance(by: .seconds(1))
        let finishing = Task { await controller.finish() }
        try? await Task.sleep(for: .milliseconds(50))
        gate.open()
        await finishing.value
        #expect(await controller.state == .failed(.microphoneUnavailable))
        #expect(!gate.timedOut)
    }

    @Test func tapWithAFailingStartShowsNothing() async {
        input.failStarts(with: .audioFormat)
        let controller = makeController()
        let log = StateLog(controller)
        await controller.begin()
        capture.waitForControl()
        await controller.cancel()
        // The failure may reach the controller after the tap; it must not show up late.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await controller.state == .idle)
        #expect(await eventually { log.all.last == .idle })
        #expect(!log.all.contains { $0.showsPill })
    }

    // Latency marks: the app begins "insert" at every key release. A release that inserts nothing drops its mark,
    // and only a release ends one, so no later insert closes a stale mark with a wrong duration.

    @Test func insertedDictationEndsTheInsertMark() async {
        let controller = makeController()
        await dictate(controller, tone())
        #expect(await controller.state == .inserted(.pasted))
        #expect(signposts.endedInserts == 1)
        #expect(!signposts.isInsertOpen)
    }

    @Test func failedRecognitionDropsTheInsertMark() async {
        let transcriber = FakeTranscriber("")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber)
        await dictate(controller, tone())
        #expect(await controller.state == .failed(.recognitionFailed))
        #expect(!signposts.isInsertOpen)
    }

    @Test func silenceDropsTheInsertMark() async {
        let controller = makeController()
        await dictate(controller, Array(repeating: 0, count: 16_000))
        #expect(await controller.state == .failed(.nothingHeard))
        #expect(!signposts.isInsertOpen)
    }

    @Test func shortHoldDropsTheInsertMark() async {
        let controller = makeController()
        await controller.begin()
        await controller.confirm()
        clock.advance(by: .milliseconds(200))
        signposts.beginInsert()
        await controller.finish()
        #expect(await controller.state == .idle)
        #expect(!signposts.isInsertOpen)
    }

    /// The hotkey may send `finish` without `confirm` when its tick is still queued.
    @Test func releaseWithAKnownFailureDropsTheInsertMark() async {
        let controller = makeController(modelReady: false)
        await controller.begin()
        clock.advance(by: .milliseconds(200))
        signposts.beginInsert()
        await controller.finish()
        #expect(await controller.state == .failed(.modelMissing))
        #expect(!signposts.isInsertOpen)
    }

    @Test func releaseAfterADisconnectDropsTheInsertMark() async {
        let controller = makeController()
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.emit(.deviceLost)
        #expect(await eventually { await controller.state == .failed(.microphoneDisconnected) })
        signposts.beginInsert()
        await controller.finish()
        #expect(!signposts.isInsertOpen)
    }

    /// The limit ends the recording without a key release: it ends no mark, and the later release drops its own.
    @Test func timeLimitEndsNoInsertMark() async {
        let controller = makeController()
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        // Left open by an earlier release.
        signposts.beginInsert()
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: .seconds(181))
        #expect(await eventually { await controller.state == .inserted(.pasted) })
        #expect(signposts.endedInserts == 0)
        #expect(!signposts.isInsertOpen)
        signposts.beginInsert()
        await controller.finish()
        #expect(!signposts.isInsertOpen)
    }

    /// "Erneut versuchen" has no key down or release: it drops the marks of a tap and of a release before it.
    @Test func retryDropsOpenMarks() async {
        let transcriber = FakeTranscriber("")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber)
        await dictate(controller, tone())
        signposts.beginPill()
        signposts.beginInsert()
        await transcriber.respond(with: .success("Zweiter Versuch."))
        await controller.retry()
        #expect(await controller.state == .inserted(.pasted))
        #expect(!signposts.isPillOpen)
        #expect(!signposts.isInsertOpen)
        #expect(signposts.endedInserts == 0)
    }

    @Test func coldStartIsMarked() async {
        let controller = makeController()
        await controller.begin()
        capture.waitForControl()
        #expect(signposts.endedMicrophoneStarts == 1)
        await controller.cancel()
    }

    /// A key pressed and released while the last dictation is still recognized does nothing; that dictation's mark
    /// stays open until its text is inserted.
    @Test func releaseDuringRecognitionKeepsTheRunningInsertMark() async {
        let transcriber = FakeTranscriber("Hallo Welt.")
        await transcriber.holdNext()
        let controller = makeController(transcriber: transcriber)
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        clock.advance(by: .seconds(1))
        signposts.beginInsert()
        let finishing = Task { await controller.finish() }
        #expect(await eventually { await transcriber.isHeld })
        await controller.begin()
        await controller.finish()
        #expect(signposts.isInsertOpen)
        await transcriber.resume()
        await finishing.value
        #expect(await controller.state == .inserted(.pasted))
        #expect(signposts.endedInserts == 1)
    }
}
