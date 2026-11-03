import CoreFoundation
import Testing
import ZackCore

@testable import ZackDesktop

/// Shortcuts that act on a dictation. As in `DictationContextTests`, only the system interfaces
/// are fakes: focus, clipboard, keystrokes, audio source and clock.
@MainActor
struct DictationShortcutTests {
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
    /// Real latency marks that write nothing to the log `scripts/latency.sh` reads.
    let signposts = Signposts(signposter: .disabled)
    /// Set by `makeController`; with a cleaner, `dictate` waits for the first prewarm.
    let hasCleaner = TestValue(false)
    let correction = FakeTranscriber("Das Treffen ist am Dienstag, nein, am Mittwoch.")
    let cleaner = StubCleaner(output: "Das Treffen ist am Mittwoch.")
    let cleaned = "Das Treffen ist am Mittwoch."
    let ruleText = "Das Treffen ist am Dienstag, nein, am Mittwoch."
    var emptyField: FocusSnapshot {
        FocusSnapshot(element: field, selection: TextRange(location: 0, length: 0), textBeforeCursor: "")
    }
    /// Runs in the next paste, while the inserter stands on the main thread.
    let pasteHook = TestValue<(@Sendable () async -> Void)?>(nil)

    init() {
        keystrokes = FakeKeystrokes(clipboard: clipboard)
        capture = MicrophoneCapture(input: input)
    }

    /// Runs `action` on its own task and holds the main thread, and so the paste, until it ends. Bounded; a hang
    /// shows as a failed expectation.
    nonisolated static func runDuringPaste(_ action: @escaping @Sendable () async -> Void) {
        let done = TestValue(false)
        Task.detached {
            await action()
            done.set(true)
        }
        _ = eventuallyBlocking { done.current }
    }

    func makeController(
        transcriber: any Transcriber = FakeTranscriber("Hallo Welt."), cleaner: (any Cleaner)? = nil,
        focus: FakeFocusSource? = nil, memory: CursorMemory = CursorMemory(),
        language: @escaping @Sendable () -> DictationLanguage = { .german }
    ) -> DictationController<TestClock> {
        hasCleaner.set(cleaner != nil)
        let inserter = Inserter(
            clipboard: clipboard, keystrokes: keystrokes,
            canPostKeystrokes: { [pasteHook] in
                if let action = pasteHook.current {
                    pasteHook.set(nil)
                    Self.runDuringPaste(action)
                }
                return true
            }, sleep: { _ in })
        return DictationController(
            capture: capture, transcriber: transcriber, inserter: inserter, clock: clock,
            makeProcessor: { TextProcessor(cleaner: cleaner) }, modelReady: { true }, microphoneAllowed: { true },
            signposts: signposts, focus: focus, memory: memory,
            language: language)
    }

    /// Key down, pill shown, `samples` spoken, key up after one second. Latency marks begin as in the app: at key
    /// down and at every key release.
    func dictate(_ controller: DictationController<TestClock>, _ samples: [Float], app: FrontApp? = nil) async {
        signposts.beginPill()
        await controller.begin(app: app)
        // The microphone starts in the background; audio arrives once it runs.
        capture.waitForControl()
        await controller.confirm()
        // The first prewarm runs in the background; a release before it would cancel it. Ticker and prewarm loop
        // then both sleep on the clock.
        if hasCleaner.current { _ = await eventually { clock.sleeperCount == 2 } }
        input.push(samples)
        clock.advance(by: .seconds(1))
        signposts.beginInsert()
        await controller.finish()
    }

    /// True if `task` ends within `limit`, real time. Well under the cleaner's own limit of 2 s, so a cleanup only
    /// ends in time when it was cancelled.
    func endsSoon(_ task: Task<Void, Never>, within limit: Duration = .seconds(1)) async -> Bool {
        let ended = TestValue(false)
        Task {
            await task.value
            ended.set(true)
        }
        return await eventually(within: limit) { ended.current }
    }

    // Esc after the release

    @Test func escDuringRecognitionInsertsNothing() async {
        let transcriber = FakeTranscriber("Der Server läuft.")
        await transcriber.holdNext()
        let controller = makeController(transcriber: transcriber)
        let done = Task { await dictate(controller, tone()) }
        #expect(await eventually { await controller.state == .recognizing })
        await controller.abort()
        await transcriber.resume()
        await done.value
        #expect(await controller.state == .notice(.cancelled))
        #expect(keystrokes.pasted.isEmpty)
        #expect(await controller.lastText == "Der Server läuft.")
        #expect(!signposts.isInsertOpen)
    }

    @Test func escDuringCleaningStopsTheCleanerAndKeepsTheRuleText() async {
        let controller = makeController(
            transcriber: FakeTranscriber("Das Treffen ist am Dienstag, nein, am Mittwoch."), cleaner: HangingCleaner())
        let done = Task { await dictate(controller, tone()) }
        #expect(await eventually { await controller.state == .cleaning })
        await controller.abort()
        await done.value
        #expect(keystrokes.pasted.isEmpty)
        #expect(await controller.lastText == "Das Treffen ist am Dienstag, nein, am Mittwoch.")
    }

    @Test func escOutsideProcessingDoesNothing() async {
        let controller = makeController()
        await dictate(controller, tone())
        await controller.abort()
        #expect(await controller.state == .inserted(.pasted))
    }

    /// Esc does not wait for the cleaner's limit, so the next key down is taken at once.
    @Test func escDuringCleaningDoesNotWaitForTheCleanerLimit() async {
        let controller = makeController(
            transcriber: FakeTranscriber("Das Treffen ist am Dienstag, nein, am Mittwoch."), cleaner: HangingCleaner())
        let done = Task { await dictate(controller, tone()) }
        #expect(await eventually { await controller.state == .cleaning })
        await controller.abort()
        #expect(await endsSoon(done))
        await done.value
        #expect(await controller.state == .notice(.cancelled))
    }

    /// Esc before the cleanup: the cleaner is not waited for, and "KI glättet …" never replaces "Abgebrochen".
    @Test func escDuringRecognitionSkipsTheCleanup() async {
        let transcriber = FakeTranscriber("Das Treffen ist am Dienstag, nein, am Mittwoch.")
        await transcriber.holdNext()
        let controller = makeController(transcriber: transcriber, cleaner: HangingCleaner())
        let done = Task { await dictate(controller, tone()) }
        #expect(await eventually { await transcriber.isHeld })
        await controller.abort()
        await transcriber.resume()
        #expect(await endsSoon(done))
        await done.value
        #expect(await controller.state == .notice(.cancelled))
        #expect(keystrokes.pasted.isEmpty)
        #expect(await controller.lastText == "Das Treffen ist am Dienstag, nein, am Mittwoch.")
    }

    /// A recognition that turns out empty after Esc fails silently: no last dictation, the pill stays.
    @Test func escBeforeAnEmptyResultKeepsTheCancelledPill() async {
        let transcriber = FakeTranscriber("")
        await transcriber.holdNext()
        let controller = makeController(transcriber: transcriber)
        let done = Task { await dictate(controller, tone()) }
        #expect(await eventually { await controller.state == .recognizing })
        await controller.abort()
        await transcriber.resume()
        await done.value
        #expect(await controller.state == .notice(.cancelled))
        #expect(await controller.lastText == nil)
    }

    /// Regression: a second Esc overwrote the mark of the first, so its recognition pasted once it ended.
    @Test func secondEscKeepsTheFirstAbortedRetrySilent() async {
        let transcriber = QueuedTranscriber([
            .failure(.engineUnavailable("test")), .success("Der Server läuft."), .success("Der Server läuft nicht."),
        ])
        let controller = makeController(transcriber: transcriber)
        await dictate(controller, tone())
        #expect(await controller.state == .failed(.recognitionFailed))
        // "Erneut versuchen" stays offered while the notice shows: the audio is kept until a recognition succeeds.
        let first = Task { await controller.retry() }
        #expect(await eventually { await transcriber.held == 1 })
        await controller.abort()
        let second = Task { await controller.retry() }
        #expect(await eventually { await transcriber.held == 2 })
        await controller.abort()
        await transcriber.release(call: 1)
        await first.value
        #expect(keystrokes.pasted.isEmpty)
        #expect(await controller.state == .notice(.cancelled))
        await transcriber.release(call: 2)
        await second.value
        #expect(keystrokes.pasted.isEmpty)
        #expect(await controller.lastText == "Der Server läuft nicht.")
    }

    /// The first retry fails only after the second Esc: no failure replaces "Abgebrochen".
    @Test func secondEscKeepsALateFailureOfTheFirstRetrySilent() async {
        let transcriber = QueuedTranscriber([
            .failure(.engineUnavailable("test")), .failure(.engineUnavailable("test")),
            .success("Der Server läuft nicht."),
        ])
        let controller = makeController(transcriber: transcriber)
        await dictate(controller, tone())
        let first = Task { await controller.retry() }
        #expect(await eventually { await transcriber.held == 1 })
        await controller.abort()
        let second = Task { await controller.retry() }
        #expect(await eventually { await transcriber.held == 2 })
        await controller.abort()
        await transcriber.release(call: 1)
        await first.value
        #expect(await controller.state == .notice(.cancelled))
        await transcriber.release(call: 2)
        await second.value
        #expect(await controller.lastText == "Der Server läuft nicht.")
    }

    /// A retry is not in the hotkey stream, so a new dictation can start beside it. The replaced retry ends silently,
    /// without "KI glättet …", and does not overwrite the newer last dictation.
    @Test func dictationAfterAnAbortedRetryKeepsTheRetrySilent() async {
        let transcriber = QueuedTranscriber([
            .failure(.engineUnavailable("test")), .success("Das Treffen ist am Dienstag, nein, am Mittwoch."),
            .success("Der Server läuft nicht."),
        ])
        let controller = makeController(
            transcriber: transcriber, cleaner: StubCleaner(output: "Das Treffen ist am Mittwoch."))
        await dictate(controller, tone())
        let retry = Task { await controller.retry() }
        #expect(await eventually { await transcriber.held == 1 })
        await controller.abort()
        let dictation = Task { await dictate(controller, tone()) }
        #expect(await eventually { await transcriber.held == 2 })
        await controller.abort()
        await transcriber.release(call: 2)
        await dictation.value
        await transcriber.release(call: 1)
        await retry.value
        #expect(keystrokes.pasted.isEmpty)
        #expect(await controller.state == .notice(.cancelled))
        #expect(await controller.lastText == "Der Server läuft nicht.")
    }

    /// The app shares one cleaner: a replaced retry that ends during the next recording keeps that recording's
    /// prewarmed session.
    @Test func abortedRetryLeavesTheNextRecordingsPrewarmAlone() async {
        let cleaner = RecordingCleaner()
        let transcriber = QueuedTranscriber([.failure(.engineUnavailable("test")), .success("Der Server läuft.")])
        let controller = makeController(transcriber: transcriber, cleaner: cleaner)
        await dictate(controller, tone())
        let retry = Task { await controller.retry() }
        #expect(await eventually { await transcriber.held == 1 })
        await controller.abort()
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        // Ticker and prewarm loop sleep on the clock once the first prewarm ran.
        #expect(await eventually { clock.sleeperCount == 2 })
        let discards = cleaner.discards
        await transcriber.release(call: 1)
        await retry.value
        #expect(cleaner.discards == discards)
        await controller.cancel()
    }

    @Test func cancelledPillHides() async {
        let transcriber = FakeTranscriber("Der Server läuft.")
        await transcriber.holdNext()
        let controller = makeController(transcriber: transcriber)
        let done = Task { await dictate(controller, tone()) }
        #expect(await eventually { await controller.state == .recognizing })
        await controller.abort()
        await transcriber.resume()
        await done.value
        // The only sleeper left is the reset of the notice.
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: DictationLimits.failureVisible)
        #expect(await eventually { await controller.state == .idle })
    }

    // A password field found after the result was kept (audio and result are dropped)

    /// Regression: Esc kept the text as the last dictation, and the late verdict left it for ⌃⌥V.
    @Test func latePasswordVerdictAfterEscDropsTheLastDictation() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let transcriber = FakeTranscriber("geheim")
        await transcriber.holdNext()
        let controller = makeController(transcriber: transcriber, focus: focus)
        let done = Task { await dictate(controller, tone(), app: safari) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        #expect(await eventually { await transcriber.isHeld })
        await controller.abort()
        await transcriber.resume()
        await done.value
        #expect(await controller.lastText == "geheim")
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.lastText == nil })
        await controller.insertLast(app: textEdit)
        #expect(await controller.state == .notice(.noLastDictation))
        #expect(keystrokes.pasted.isEmpty)
    }

    /// Regression: the text was inserted (it had already landed), but the last dictation, ⌃⌥O and the cursor
    /// memory kept it after the late verdict.
    @Test func latePasswordVerdictAfterTheInsertDropsTheLastDictation() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let memory = CursorMemory()
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus, memory: memory)
        let done = Task { await dictate(controller, tone(), app: textEdit) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        await done.value
        #expect(keystrokes.pasted == [cleaned])
        #expect(await controller.canReplaceWithRuleText)
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
        #expect(await eventually { await controller.lastText == nil })
        #expect(await !controller.canReplaceWithRuleText)
        #expect(memory.text(app: textEdit, element: nil) == nil)
        await controller.replaceWithRuleText()
        #expect(await controller.state == .notice(.noCleanedVersion))
        #expect(keystrokes.pasted == [cleaned])
        #expect(clipboard.text != ruleText)
    }

    /// A late verdict without a password field changes nothing.
    @Test func lateVerdictWithoutPasswordFieldKeepsTheLastDictation() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let memory = CursorMemory()
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus, memory: memory)
        let done = Task { await dictate(controller, tone(), app: textEdit) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        await done.value
        focus.releaseHeldRead(returning: FocusSnapshot(element: field, textBeforeCursor: ""))
        #expect(await eventually { await controller.keyDownSettled })
        #expect(await controller.lastText == cleaned)
        #expect(await controller.canReplaceWithRuleText)
        #expect(memory.text(app: textEdit, element: nil) == cleaned)
    }

    /// The verdict comes while the text is being pasted: it lands, but nothing of it is kept.
    @Test func passwordVerdictDuringThePasteKeepsNothing() async {
        let focus = FakeFocusSource()
        focus.holdNextRead()
        let memory = CursorMemory()
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus, memory: memory)
        let field = field
        pasteHook.set {
            focus.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
            _ = await eventually { await controller.keyDownIsSecure }
        }
        let done = Task { await dictate(controller, tone(), app: textEdit) }
        #expect(await eventually { await controller.state == .recognizing && clock.sleeperCount > 0 })
        clock.advance(by: DictationLimits.recheckGrace)
        await done.value
        #expect(keystrokes.pasted == [cleaned])
        #expect(await controller.keyDownIsSecure)
        #expect(await controller.lastText == nil)
        #expect(await !controller.canReplaceWithRuleText)
        #expect(memory.text(app: textEdit, element: nil) == nil)
    }

    // ⌃⌥V

    @Test func insertLastUsesTheNewPlace() async {
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field, selection: TextRange(location: 0, length: 0), textBeforeCursor: ""))
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."), focus: focus)
        await dictate(controller, tone(), app: textEdit)
        focus.queue(
            FocusSnapshot(
                element: other, selection: TextRange(location: 11, length: 0), textBeforeCursor: "Ich glaube,"))
        await controller.insertLast(app: textEdit)
        #expect(keystrokes.pasted == ["Der Server läuft.", " der Server läuft."])
        #expect(await controller.state == .inserted(.pasted))
    }

    @Test func insertLastJoinsWithTheLanguageOfTheDictation() async {
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field, selection: TextRange(location: 0, length: 0), textBeforeCursor: ""))
        let calls = TestValue(0)
        let current = TestValue(DictationLanguage.english)
        let controller = makeController(
            transcriber: FakeTranscriber("Meeting tomorrow."), focus: focus,
            language: {
                calls.set(calls.current + 1)
                return current.current
            })
        await dictate(controller, tone(), app: textEdit)
        current.set(.german)
        let readsBefore = calls.current
        focus.queue(
            FocusSnapshot(
                element: other, selection: TextRange(location: 11, length: 0), textBeforeCursor: "I think the"))
        await controller.insertLast(app: textEdit)
        #expect(keystrokes.pasted.last == " meeting tomorrow.")
        #expect(calls.current == readsBefore)
    }

    @Test func insertLastWithoutDictationShowsAHint() async {
        let controller = makeController()
        await controller.insertLast(app: textEdit)
        #expect(await controller.state == .notice(.noLastDictation))
        #expect(keystrokes.pasted.isEmpty)
    }

    @Test func insertLastIntoPasswordFieldInsertsNothing() async {
        let focus = FakeFocusSource()
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."), focus: focus)
        await dictate(controller, tone(), app: textEdit)
        focus.queue(FocusSnapshot(element: other, isSecure: true))
        await controller.insertLast(app: safari)
        #expect(await controller.state == .notice(.passwordFieldNotInserted))
        #expect(keystrokes.pasted == ["Der Server läuft."])
        #expect(clipboard.writes == 1)
    }

    @Test func lastTextHasNoLeadingSpace() async {
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field))
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."), focus: focus)
        await dictate(controller, tone(), app: terminal)
        await dictate(controller, tone(), app: terminal)
        #expect(keystrokes.pasted.last == " Der Server läuft.")
        #expect(await controller.lastText == "Der Server läuft.")
    }

    @Test func insertLastDuringADictationIsIgnored() async {
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."))
        await dictate(controller, tone())
        await controller.begin()
        await controller.insertLast(app: textEdit)
        #expect(keystrokes.pasted == ["Der Server läuft."])
        #expect(await controller.state == .listening)
    }

    @Test func dictationStartedDuringInsertLastKeepsThePill() async {
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."))
        await dictate(controller, tone())
        pasteHook.set { await controller.begin() }
        await controller.insertLast(app: textEdit)
        #expect(keystrokes.pasted.count == 2)
        #expect(await controller.state == .listening)
    }

    @Test func secondInsertLastDuringTheFirstIsDropped() async {
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."))
        await dictate(controller, tone())
        pasteHook.set {
            // Only the first paste hooks; the second call must not get as far.
            await controller.insertLast(app: nil)
        }
        await controller.insertLast(app: textEdit)
        #expect(keystrokes.pasted == ["Der Server läuft.", "Der Server läuft."])
    }

    // ⌃⌥O

    @Test func ruleTextReplacesTheCleanedVersion() async {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        let range = TextRange(location: 0, length: cleaned.utf16.count)
        focus.setText(cleaned, at: range)
        await controller.replaceWithRuleText()
        #expect(keystrokes.pasted == [cleaned, ruleText])
        #expect(focus.selections == [range])
        #expect(await controller.state == .ruleText(.pasted))
        #expect(await controller.lastText == ruleText)
    }

    @Test func ruleTextGoesToClipboardWhenTheTextChanged() async {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        focus.setText("Das Treffen ist am Mittwoch!", at: TextRange(location: 0, length: cleaned.utf16.count))
        await controller.replaceWithRuleText()
        #expect(keystrokes.pasted == [cleaned])
        #expect(focus.selections.isEmpty)
        #expect(clipboard.text == ruleText)
        #expect(clipboard.lastWriteTransient == false)
        #expect(await controller.state == .ruleText(.clipboardOnly))
    }

    @Test func ruleTextAfterTenSecondsGoesToClipboard() async {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        focus.setText(cleaned, at: TextRange(location: 0, length: cleaned.utf16.count))
        clock.advance(by: .seconds(11))
        // The reset of the first insert wakes up too; let it hide the pill before ⌃⌥O shows its own.
        #expect(await eventually { await controller.state == .idle })
        await controller.replaceWithRuleText()
        #expect(keystrokes.pasted == [cleaned])
        #expect(focus.selections.isEmpty)
        #expect(clipboard.text == ruleText)
        #expect(await controller.state == .ruleText(.clipboardOnly))
    }

    @Test func ruleTextWithoutCleanerShowsAHint() async {
        let controller = makeController(transcriber: FakeTranscriber("Der Server läuft."))
        await dictate(controller, tone())
        await controller.replaceWithRuleText()
        #expect(await controller.state == .notice(.noCleanedVersion))
        #expect(keystrokes.pasted == ["Der Server läuft."])
    }

    @Test func ruleTextWhenFocusMovedGoesToClipboard() async {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        focus.setText(cleaned, at: TextRange(location: 0, length: cleaned.utf16.count))
        focus.queue(FocusSnapshot(element: other, selection: TextRange(location: 0, length: 0), textBeforeCursor: ""))
        await controller.replaceWithRuleText()
        #expect(keystrokes.pasted == [cleaned])
        #expect(focus.selections.isEmpty)
        #expect(clipboard.text == ruleText)
        #expect(await controller.state == .ruleText(.clipboardOnly))
    }

    @Test func newDictationEndsTheRuleTextWindow() async throws {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let transcriber = QueuedTranscriber([.success(ruleText), .success("Der Server läuft.")])
        let controller = makeController(transcriber: transcriber, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        focus.setText(cleaned, at: TextRange(location: 0, length: cleaned.utf16.count))
        #expect(await controller.canReplaceWithRuleText)
        // The second recognition waits in the queue until released; it carries no signal word.
        let second = Task { await dictate(controller, tone(), app: textEdit) }
        try #require(await eventually { await transcriber.held == 1 })
        await transcriber.release(call: 1)
        await second.value
        await controller.replaceWithRuleText()
        #expect(await controller.state == .notice(.noCleanedVersion))
    }

    /// A tap of the key is no dictation: ⌃⌥O still replaces the cleaned version afterwards.
    @Test func tapKeepsTheRuleTextWindow() async {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        let range = TextRange(location: 0, length: cleaned.utf16.count)
        focus.setText(cleaned, at: range)
        await controller.begin(app: textEdit)
        await controller.cancel()
        #expect(await controller.canReplaceWithRuleText)
        await controller.replaceWithRuleText()
        #expect(keystrokes.pasted == [cleaned, ruleText])
        #expect(focus.selections == [range])
        #expect(await controller.state == .ruleText(.pasted))
    }

    /// A release after the threshold but before the pill's tick ends a dictation without `confirm`. It still ends
    /// the entry, also when it fails.
    @Test func dictationWithoutConfirmEndsTheRuleTextWindow() async {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        focus.setText(cleaned, at: TextRange(location: 0, length: cleaned.utf16.count))
        await controller.begin(app: textEdit)
        capture.waitForControl()
        input.push(Array(repeating: 0, count: 16_000))
        clock.advance(by: .seconds(1))
        await controller.finish()
        #expect(await controller.state == .failed(.nothingHeard))
        #expect(await !controller.canReplaceWithRuleText)
        await controller.replaceWithRuleText()
        #expect(await controller.state == .notice(.noCleanedVersion))
        #expect(keystrokes.pasted == [cleaned])
    }

    @Test func keyDownDuringTheSelectCollapsesTheSelection() async throws {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        let range = TextRange(location: 0, length: cleaned.utf16.count)
        focus.setText(cleaned, at: range)
        focus.holdNextSelect()
        let replace = Task { await controller.replaceWithRuleText() }
        try #require(await eventually { focus.heldSelects == 1 })
        await controller.begin(app: textEdit)
        focus.releaseSelect()
        await replace.value
        #expect(focus.selections == [range, TextRange(location: cleaned.utf16.count, length: 0)])
        #expect(keystrokes.pasted == [cleaned])
        #expect(await controller.state == .listening)
    }

    /// A field reporting a start near `Int.max`: collapsing behind the selected text must not overflow.
    @Test func keyDownDuringTheSelectAtAHugeStartDoesNotOverflow() async throws {
        let focus = FakeFocusSource()
        let start = Int.max - 2
        focus.queue(
            FocusSnapshot(element: field, selection: TextRange(location: start, length: 0), textBeforeCursor: ""))
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        let range = TextRange(location: start, length: cleaned.utf16.count)
        focus.setText(cleaned, at: range)
        focus.holdNextSelect()
        let replace = Task { await controller.replaceWithRuleText() }
        try #require(await eventually { focus.heldSelects == 1 })
        await controller.begin(app: textEdit)
        focus.releaseSelect()
        await replace.value
        #expect(focus.selections == [range])
        #expect(keystrokes.pasted == [cleaned])
        #expect(await controller.state == .listening)
    }

    @Test func ruleTextGoesToClipboardWhenTheSelectFails() async {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        focus.setText(cleaned, at: TextRange(location: 0, length: cleaned.utf16.count))
        focus.selectSucceeds = false
        await controller.replaceWithRuleText()
        #expect(keystrokes.pasted == [cleaned])
        #expect(clipboard.text == ruleText)
        #expect(await controller.state == .ruleText(.clipboardOnly))
    }

    @Test func ruleTextGoesToClipboardWithoutAKnownStart() async {
        let focus = FakeFocusSource()
        focus.queue(FocusSnapshot(element: field, textBeforeCursor: ""))
        let controller = makeController(transcriber: correction, cleaner: cleaner, focus: focus)
        await dictate(controller, tone(), app: textEdit)
        await controller.replaceWithRuleText()
        #expect(keystrokes.pasted == [cleaned])
        #expect(focus.selections.isEmpty)
        #expect(clipboard.text == ruleText)
        #expect(await controller.state == .ruleText(.clipboardOnly))
    }

    @Test func ruleTextCountsUTF16UnitsForTheRange() async {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let emoji = "Das Treffen ist am Mittwoch \u{1F600}."
        let controller = makeController(
            transcriber: correction, cleaner: StubCleaner(output: emoji), focus: focus)
        await dictate(controller, tone(), app: textEdit)
        let range = TextRange(location: 0, length: emoji.utf16.count)
        #expect(emoji.utf16.count != emoji.count)
        focus.setText(emoji, at: range)
        await controller.replaceWithRuleText()
        #expect(focus.selections == [range])
        #expect(await controller.state == .ruleText(.pasted))
    }
}
