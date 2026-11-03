import CoreFoundation
import Testing
import ZackCore

@testable import ZackDesktop

/// Mode and text before the cursor in a dictation. As in `DictationControllerTests`, only the system
/// interfaces are fakes: focus, clipboard, keystrokes, audio source and clock.
@MainActor
struct DictationContextTests {
    let input = FakeAudioInput()
    let clock = TestClock()
    let clipboard = FakeClipboard()
    let keystrokes: FakeKeystrokes
    let capture: MicrophoneCapture
    /// One pid for every app, so the element decides.
    let field = FocusElement(pid: 42, reference: "field-1" as CFString)
    let other = FocusElement(pid: 42, reference: "field-2" as CFString)
    let terminal = FrontApp(bundleID: "com.apple.Terminal", pid: 42)
    let textEdit = FrontApp(bundleID: "com.apple.TextEdit", pid: 42)
    let safari = FrontApp(bundleID: "com.apple.Safari", pid: 42)
    /// Set by `makeController`; with a cleaner, `dictate` waits for the first prewarm.
    let hasCleaner = TestValue(false)

    init() {
        keystrokes = FakeKeystrokes(clipboard: clipboard)
        capture = MicrophoneCapture(input: input)
    }

    func makeController(
        transcriber: FakeTranscriber = FakeTranscriber("Hallo Welt."), cleaner: (any Cleaner)? = nil,
        focus: FakeFocusSource? = nil, memory: CursorMemory = CursorMemory(),
        codeMode: @escaping @Sendable (String?) -> TextMode = { _ in .prose }
    ) -> DictationController<TestClock> {
        hasCleaner.set(cleaner != nil)
        let inserter = Inserter(
            clipboard: clipboard, keystrokes: keystrokes, canPostKeystrokes: { true }, sleep: { _ in })
        return DictationController(
            capture: capture, transcriber: transcriber, inserter: inserter, clock: clock,
            makeProcessor: { TextProcessor(cleaner: cleaner) }, modelReady: { true }, microphoneAllowed: { true },
            focus: focus, memory: memory, codeMode: codeMode)
    }

    /// Key down in `app`, pill shown, `samples` spoken, key up after one second.
    func dictate(_ controller: DictationController<TestClock>, _ samples: [Float], app: FrontApp?) async {
        await controller.begin(app: app)
        // The microphone starts in the background; audio arrives once it runs.
        capture.waitForControl()
        await controller.confirm()
        // The first prewarm runs in the background; a release before it would cancel it. Ticker and prewarm loop
        // then both sleep on the clock.
        if hasCleaner.current { _ = await eventually { clock.sleeperCount == 2 } }
        input.push(samples)
        clock.advance(by: .seconds(1))
        await controller.finish()
    }

    @Test func secondDictationGetsASpaceFromMemory() async {
        // Regression for the known limit of 1a: consecutive dictations ran together ("steckt.Samsungs").
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field))  // app gives no text
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."), focus: focus)
        await dictate(controller, tone(), app: terminal)
        await dictate(controller, tone(), app: terminal)
        #expect(keystrokes.pasted == ["Der Server läuft.", " Der Server läuft."])
    }

    @Test func accessibilityTextDecidesSpaceAndCase() async {
        let focus = FakeFocusSource()
        focus.queue(
            FocusSnapshot(
                element: field, selection: TextRange(location: 11, length: 0), textBeforeCursor: "Ich glaube,"))
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."), focus: focus)
        await dictate(controller, tone(), app: textEdit)
        #expect(keystrokes.pasted == [" der Server läuft."])
    }

    /// The text before the cursor stays in memory only until the dictation ends.
    @Test func keyDownSnapshotIsDroppedWhenTheDictationEnds() async {
        let focus = FakeFocusSource()
        focus.queue(
            FocusSnapshot(
                element: field, selection: TextRange(location: 15, length: 0), textBeforeCursor: "Max Mustermann,"))
        let controller = makeController(focus: focus)
        await dictate(controller, tone(), app: textEdit)
        #expect(await controller.state == .inserted(.pasted))
        #expect(await controller.focusRead == nil)
    }

    /// A tap reads the focus as well; its snapshot goes with the tap.
    @Test func keyDownSnapshotIsDroppedAfterATap() async {
        let focus = FakeFocusSource()
        focus.queue(
            FocusSnapshot(
                element: field, selection: TextRange(location: 15, length: 0), textBeforeCursor: "Max Mustermann,"))
        let controller = makeController(focus: focus)
        await controller.begin(app: textEdit)
        #expect(await eventually { focus.reads == 1 })
        await controller.cancel()
        #expect(await controller.focusRead == nil)
    }

    /// A dictation that ends without a recognition (nothing heard) drops it too.
    @Test func keyDownSnapshotIsDroppedWhenNothingWasHeard() async {
        let focus = FakeFocusSource()
        focus.queue(
            FocusSnapshot(
                element: field, selection: TextRange(location: 15, length: 0), textBeforeCursor: "Max Mustermann,"))
        let controller = makeController(focus: focus)
        await dictate(controller, Array(repeating: 0, count: 16_000), app: textEdit)
        #expect(await controller.state == .failed(.nothingHeard))
        #expect(await controller.focusRead == nil)
    }

    @Test func codeAppUsesCodeMode() async {
        let cleaner = RecordingCleaner()
        let controller = makeController(
            transcriber: FakeTranscriber("deploy Punkt sh"), cleaner: cleaner,
            codeMode: { $0 == "com.apple.Terminal" ? .code : .prose })
        await dictate(controller, tone(), app: terminal)
        #expect(keystrokes.pasted == ["deploy.sh"])
        #expect(cleaner.prewarms.first?.mode == .code)
    }

    @Test func proseAppKeepsSpokenFileName() async {
        let controller = makeController(
            transcriber: FakeTranscriber("deploy Punkt sh"), codeMode: { $0 == "com.apple.Terminal" ? .code : .prose })
        await dictate(controller, tone(), app: textEdit)
        #expect(keystrokes.pasted == ["deploy Punkt sh"])
    }

    @Test func changedFocusAtReleaseIsReadAgain() async {
        let focus = FakeFocusSource()
        focus.queue(
            FocusSnapshot(element: field, selection: TextRange(location: 0, length: 0), textBeforeCursor: ""),
            FocusSnapshot(
                element: other, selection: TextRange(location: 11, length: 0), textBeforeCursor: "Ich glaube,"))
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."), focus: focus)
        await dictate(controller, tone(), app: textEdit)
        #expect(keystrokes.pasted == [" der Server läuft."])
    }

    @Test func slowFocusSourceDoesNotHoldTheInsert() async {
        let focus = FakeFocusSource()
        focus.holdReads()
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."), focus: focus)
        let done = Task { await dictate(controller, tone(), app: textEdit) }
        // State first: once it is `.recognizing` the ticker no longer sleeps, so the sleeper is the grace wait.
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        await done.value
        #expect(keystrokes.pasted == ["Der Server läuft."])
        focus.releaseReads()
    }

    @Test func passwordFieldAtKeyDownDropsTheAudio() async {
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field, isSecure: true))
        let transcriber = FakeTranscriber("geheim")
        let controller = makeController(transcriber: transcriber, focus: focus)
        await dictate(controller, tone(), app: safari)
        #expect(await controller.state == .failed(.passwordField))
        #expect(await transcriber.calls == 0)
        #expect(keystrokes.pasted.isEmpty)
        #expect(clipboard.text == nil)
    }

    /// The key-down snapshot ends the recording while the key is still held, not only at release.
    @Test func passwordFieldEndsTheRecordingWhileHeld() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let controller = makeController(focus: focus)
        await controller.begin(app: safari)
        capture.waitForControl()
        await controller.confirm()
        #expect(await eventually { focus.heldReads == 1 })
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.state == .failed(.passwordField) })
        capture.waitForControl()
        #expect(input.stopCount == 1)
    }

    /// Inside the tap window the verdict drops the audio at once and shows once the pill would appear.
    @Test func passwordFieldInTheTapWindowShowsAtTheThreshold() async {
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field, isSecure: true))
        let controller = makeController(focus: focus)
        await controller.begin(app: safari)
        #expect(await eventually { input.stopCount == 1 })
        #expect(await controller.state == .listening)
        await controller.confirm()
        #expect(await controller.state == .failed(.passwordField))
    }

    /// A cold microphone may still be starting when the verdict comes; the pill does not wait for the start.
    @Test func passwordFieldDoesNotWaitForAColdStart() async {
        let gate = input.blockNextStart()
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field, isSecure: true))
        let controller = makeController(focus: focus)
        let log = StateLog(controller)
        await controller.begin(app: safari)
        await controller.confirm()
        #expect(await eventually { log.all.last == .failed(.passwordField) })
        #expect(!gate.timedOut)
        gate.open()
        capture.waitForControl()
        #expect(input.stopCount == 1)
    }

    /// The key-down read comes back after the release grace, while the recognition runs: nothing is inserted.
    @Test func passwordVerdictAfterTheGraceInsertsNothing() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let transcriber = FakeTranscriber("geheim")
        await transcriber.holdNext()
        let controller = makeController(transcriber: transcriber, focus: focus)
        let done = Task { await dictate(controller, tone(), app: safari) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        #expect(await eventually { await transcriber.isHeld })
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.keyDownIsSecure })
        await transcriber.resume()
        await done.value
        #expect(await controller.state == .failed(.passwordField))
        #expect(keystrokes.pasted.isEmpty)
        #expect(clipboard.text == nil)
        #expect(await controller.lastText == nil)
    }

    /// "Erneut versuchen" records nothing, but its focus read comes back the same way.
    @Test func passwordVerdictAfterTheGraceDropsARetry() async {
        let focus = FakeFocusSource()
        let transcriber = FakeTranscriber("geheim")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber, focus: focus)
        await dictate(controller, tone(), app: safari)
        #expect(await controller.state == .failed(.recognitionFailed))
        // Key-down read and recheck of the failed dictation are done, so the hold hits the retry's read.
        #expect(await eventually { focus.reads == 2 })
        await transcriber.respond(with: .success("geheim"))
        await transcriber.holdNext()
        focus.holdNextRead()
        let done = Task { await controller.retry() }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        #expect(await eventually { await transcriber.isHeld })
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.keyDownIsSecure })
        await transcriber.resume()
        await done.value
        #expect(await controller.state == .failed(.passwordField))
        #expect(keystrokes.pasted.isEmpty)
        #expect(clipboard.text == nil)
        #expect(await !controller.canRetry)
    }

    /// A password field at "Erneut versuchen" found in time drops the kept audio as a late verdict does.
    @Test func passwordVerdictInTimeDropsTheRetryAudio() async {
        let focus = FakeFocusSource()
        let transcriber = FakeTranscriber("geheim")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber, focus: focus)
        await dictate(controller, tone(), app: safari)
        #expect(await controller.canRetry)
        // Key-down read and recheck of the failed dictation are done, so the queue serves the retry's read.
        #expect(await eventually { focus.reads == 2 })
        focus.queue(FocusSnapshot(element: field, isSecure: true))
        await transcriber.respond(with: .success("geheim"))
        await controller.retry()
        #expect(await controller.state == .failed(.passwordField))
        // Gone with the failure itself, not only once the read's own hop arrives.
        #expect(await !controller.canRetry)
        #expect(keystrokes.pasted.isEmpty)
        #expect(await transcriber.calls == 1)
    }

    /// Regression: the key-down read comes back only after the recognition failed. The audio was kept for "Erneut
    /// versuchen", and a retry inserted the password into the field in front then.
    @Test func passwordVerdictAfterAFailedRecognitionDropsTheRetryAudio() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let transcriber = FakeTranscriber("geheim")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber, focus: focus)
        let done = Task { await dictate(controller, tone(), app: safari) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        await done.value
        #expect(await controller.state == .failed(.recognitionFailed))
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.keyDownIsSecure })
        #expect(await !controller.canRetry)
        await transcriber.respond(with: .success("geheim"))
        await controller.retry()
        #expect(keystrokes.pasted.isEmpty)
        #expect(clipboard.text == nil)
        #expect(await transcriber.calls == 1)
    }

    /// The verdict comes during a recognition that then fails: no audio is kept, and the pill names the reason.
    @Test func passwordVerdictDuringAFailingRecognitionKeepsNoAudio() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let transcriber = FakeTranscriber("geheim")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        await transcriber.holdNext()
        let controller = makeController(transcriber: transcriber, focus: focus)
        let done = Task { await dictate(controller, tone(), app: safari) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        #expect(await eventually { await transcriber.isHeld })
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.keyDownIsSecure })
        await transcriber.resume()
        await done.value
        #expect(await controller.state == .failed(.passwordField))
        #expect(await !controller.canRetry)
    }

    /// A verdict during the recognition keeps the text from the cleaner as well.
    @Test func passwordVerdictDuringTheRecognitionSkipsTheCleaner() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let cleaner = RecordingCleaner()
        let transcriber = FakeTranscriber("Das Treffen ist am Dienstag, nein, am Mittwoch.")
        await transcriber.holdNext()
        let controller = makeController(transcriber: transcriber, cleaner: cleaner, focus: focus)
        let done = Task { await dictate(controller, tone(), app: safari) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        #expect(await eventually { await transcriber.isHeld })
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.keyDownIsSecure })
        await transcriber.resume()
        await done.value
        #expect(cleaner.cleans == 0)
        #expect(await controller.state == .failed(.passwordField))
        #expect(keystrokes.pasted.isEmpty)
        #expect(await controller.lastText == nil)
    }

    /// The verdict comes during the cleanup: the result goes nowhere, not even into "Letztes Diktat kopieren".
    @Test func passwordVerdictDuringTheCleanupInsertsNothing() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let cleaner = GatedCleaner()
        let controller = makeController(
            transcriber: FakeTranscriber("Das Treffen ist am Dienstag, nein, am Mittwoch."), cleaner: cleaner,
            focus: focus)
        let done = Task { await dictate(controller, tone(), app: safari) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        #expect(await eventually { cleaner.isWaiting })
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.keyDownIsSecure })
        cleaner.release()
        await done.value
        #expect(await controller.state == .failed(.passwordField))
        #expect(keystrokes.pasted.isEmpty)
        #expect(await controller.lastText == nil)
    }

    /// Regression: a tap after the failed recognition started a newer session, so the late verdict of the dictation
    /// whose audio was kept was dropped as outdated and the password audio stayed for "Erneut versuchen".
    @Test func passwordVerdictAfterAFailedRecognitionAndATapDropsTheRetryAudio() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let transcriber = FakeTranscriber("geheim")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber, focus: focus)
        let done = Task { await dictate(controller, tone(), app: safari) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        await done.value
        #expect(await controller.state == .failed(.recognitionFailed))
        // The verdict of the recording is still out, so the audio is not offered yet.
        #expect(await !controller.canRetry)
        await controller.begin(app: textEdit)
        // The tap's own read is not held; it must be back before the held one is released.
        #expect(await eventually { focus.reads == 2 })
        await controller.cancel()
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { focus.heldReads == 0 })
        #expect(await eventually { await !controller.canRetry })
        await transcriber.respond(with: .success("geheim"))
        await controller.retry()
        #expect(keystrokes.pasted.isEmpty)
        #expect(await transcriber.calls == 1)
    }

    /// While the key-down read of the failed dictation is still out, its audio is not offered and a retry does not
    /// run: the read may yet find a password field. It does, and the audio goes. Before, a retry could run and insert
    /// meanwhile, and a verdict arriving during it was matched to the retry, not to the recording.
    @Test func retryDoesNotRunWhileTheVerdictOfTheRecordingIsOut() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let transcriber = FakeTranscriber("geheim")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber, focus: focus)
        let done = Task { await dictate(controller, tone(), app: safari) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        await done.value
        #expect(await controller.state == .failed(.recognitionFailed))
        #expect(await !controller.canRetry)
        await transcriber.respond(with: .success("geheim"))
        await controller.retry()
        #expect(await transcriber.calls == 1)
        #expect(keystrokes.pasted.isEmpty)
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.keyDownIsSecure })
        #expect(await !controller.canRetry)
        await controller.retry()
        #expect(await transcriber.calls == 1)
        #expect(keystrokes.pasted.isEmpty)
        #expect(clipboard.text == nil)
    }

    /// The key-down read comes back late without a password field: the audio becomes retryable then.
    @Test func lateVerdictWithoutPasswordFieldMakesTheAudioRetryable() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let transcriber = FakeTranscriber("Der Server läuft.")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber, focus: focus)
        let done = Task { await dictate(controller, tone(), app: textEdit) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        await done.value
        #expect(await controller.state == .failed(.recognitionFailed))
        #expect(await !controller.canRetry)
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, textBeforeCursor: ""))
        #expect(await eventually { await controller.canRetry })
        await transcriber.respond(with: .success("Der Server läuft."))
        await controller.retry()
        #expect(keystrokes.pasted == ["Der Server läuft."])
    }

    /// The verdict comes back without a password field during a recognition that then fails: retryable at once.
    @Test func verdictDuringAFailingRecognitionMakesTheAudioRetryable() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let transcriber = FakeTranscriber("Der Server läuft.")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        await transcriber.holdNext()
        let controller = makeController(transcriber: transcriber, focus: focus)
        let done = Task { await dictate(controller, tone(), app: textEdit) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        #expect(await eventually { await transcriber.isHeld })
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, textBeforeCursor: ""))
        #expect(await eventually { await controller.keyDownSettled })
        await transcriber.resume()
        await done.value
        #expect(await controller.state == .failed(.recognitionFailed))
        #expect(await controller.canRetry)
    }

    /// A tap is no dictation: its verdict leaves the audio of the earlier failed recognition alone.
    @Test func passwordVerdictAfterATapKeepsTheRetryAudio() async {
        let focus = FakeFocusSource()
        let transcriber = FakeTranscriber("Der Server läuft.")
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        // Key-down read and recheck of the failed dictation are done, so the hold hits the tap's read.
        #expect(await eventually { focus.reads == 2 })
        focus.holdNextRead()
        await controller.begin(app: safari)
        #expect(await eventually { focus.heldReads == 1 })
        await controller.cancel()
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.keyDownIsSecure })
        #expect(await controller.canRetry)
        await transcriber.respond(with: .success("Der Server läuft."))
        await controller.retry()
        #expect(keystrokes.pasted == ["Der Server läuft."])
    }

    /// Released before the key-down read came back: the recognition sees the password field and does not run, and
    /// the late hop fails nothing a second time.
    @Test func passwordFieldKnownOnlyAfterReleaseSkipsTheRecognition() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let transcriber = FakeTranscriber("geheim")
        let controller = makeController(transcriber: transcriber, focus: focus)
        let log = StateLog(controller)
        let done = Task { await dictate(controller, tone(), app: safari) }
        // State first: once it is `.recognizing` the ticker no longer sleeps, so the sleeper is the grace wait.
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        await done.value
        // Gives the hop of the key-down read time to reach the actor.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(await controller.state == .failed(.passwordField))
        #expect(await transcriber.calls == 0)
        #expect(await eventually { log.all.last == .failed(.passwordField) })
        #expect(log.all.filter { $0 == .failed(.passwordField) }.count == 1)
    }

    @Test func passwordFieldOnATapStaysSilent() async {
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field, isSecure: true))
        let controller = makeController(focus: focus)
        await controller.begin(app: safari)
        await controller.cancel()
        #expect(await controller.state == .idle)
    }

    @Test func passwordFieldAtReleaseInsertsNothing() async {
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field, textBeforeCursor: ""), FocusSnapshot(element: other, isSecure: true))
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."), focus: focus)
        await dictate(controller, tone(), app: safari)
        #expect(await controller.state == .notice(.passwordFieldNotInserted))
        #expect(keystrokes.pasted.isEmpty)
        #expect(clipboard.text == nil)
        #expect(await controller.lastText == "Der Server läuft.")
    }

    @Test func passwordNoticeLeavesNoMemoryAndHides() async {
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field, textBeforeCursor: ""), FocusSnapshot(element: other, isSecure: true))
        let memory = CursorMemory()
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."), focus: focus, memory: memory)
        await dictate(controller, tone(), app: safari)
        #expect(memory.text(app: safari, element: other) == nil)
        // The only sleeper left is the reset of the notice.
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: DictationLimits.failureVisible)
        #expect(await eventually { await controller.state == .idle })
    }

    @Test func lateSnapshotOfAnEarlierDictationIsIgnored() async {
        // Dictation 1 (a tap): its key-down read hangs and arrives during dictation 2.
        let focus = FakeFocusSource()
        focus.holdNextRead()
        focus.queue(FocusSnapshot(element: field, textBeforeCursor: ""))
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."), focus: focus)
        await controller.begin(app: safari)
        // The hold must catch dictation 1's read, not dictation 2's.
        #expect(await eventually { focus.heldReads == 1 })
        await controller.cancel()
        await controller.begin(app: textEdit)
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { focus.heldReads == 0 })
        // Gives a wrongly accepted snapshot time to reach the actor before the release.
        try? await Task.sleep(for: .milliseconds(50))
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(keystrokes.pasted == ["Der Server läuft."])
    }
}
