import CoreFoundation
import Testing
import ZackCore
import ZackTestSupport

@testable import ZackDesktop

/// The term check in the dictation flow. As in `DictationShortcutTests`, only the system interfaces and the engines
/// are fakes; the processor is the real one.
@MainActor
struct DictationTermCheckTests {
    let input = FakeAudioInput()
    let clock = TestClock()
    let clipboard = FakeClipboard()
    let keystrokes: FakeKeystrokes
    let capture: MicrophoneCapture
    /// Real latency marks that write nothing to the log `scripts/latency.sh` reads.
    let signposts = Signposts(signposter: .disabled)
    let field = FocusElement(pid: 42, reference: "field-1" as CFString)
    let textEdit = FrontApp(bundleID: "com.apple.TextEdit", pid: 42)
    let homeroot = "Über Homeroot ziehe ich gitleaks."
    let homebrew = "Über Homebrew ziehe ich gitleaks."
    var emptyField: FocusSnapshot {
        FocusSnapshot(element: field, selection: TextRange(location: 0, length: 0), textBeforeCursor: "")
    }

    init() {
        keystrokes = FakeKeystrokes(clipboard: clipboard)
        capture = MicrophoneCapture(input: input)
    }

    /// Parakeet heard "Homeroot" and is unsure about it.
    func unsure() -> FakeTranscriber {
        let words = homeroot.split(separator: " ").map {
            RecognizedWord(text: String($0), confidence: $0 == "Homeroot" ? 0.35 : 0.99)
        }
        return FakeTranscriber(homeroot, words: words)
    }

    func makeController(
        transcriber: FakeTranscriber, opinion: RecordingSecondOpinion?, focus: FakeFocusSource? = nil
    ) -> DictationController<TestClock> {
        let inserter = Inserter(
            clipboard: clipboard, keystrokes: keystrokes, canPostKeystrokes: { true }, sleep: { _ in })
        return DictationController(
            capture: capture, transcriber: transcriber, inserter: inserter, clock: clock,
            makeProcessor: {
                TextProcessor(vocabulary: Vocabulary(terms: ["Homebrew", "gitleaks"]), secondOpinion: opinion)
            },
            modelReady: { true }, microphoneAllowed: { true }, signposts: signposts, focus: focus)
    }

    /// Key down, pill shown, one second spoken, key up.
    func dictate(_ controller: DictationController<TestClock>, app: FrontApp? = nil) async {
        await controller.begin(app: app)
        capture.waitForControl()
        await controller.confirm()
        input.push(tone())
        clock.advance(by: .seconds(1))
        await controller.finish()
    }

    @Test func markedDictationShowsCleaningWhileChecking() async {
        let opinion = RecordingSecondOpinion(.held(homebrew))
        let controller = makeController(transcriber: unsure(), opinion: opinion)
        let done = Task { await dictate(controller) }
        #expect(await eventually { await !opinion.calls.isEmpty })
        #expect(await controller.state == .cleaning)
        await opinion.release()
        await done.value
        #expect(await controller.state == .inserted(.pasted))
    }

    @Test func checkedTextIsInserted() async {
        let opinion = RecordingSecondOpinion(.answer(homebrew))
        let transcriber = unsure()
        let controller = makeController(transcriber: transcriber, opinion: opinion)
        await dictate(controller)
        #expect(keystrokes.pasted == [homebrew])
        #expect(await controller.lastText == homebrew)
        let calls = await opinion.calls
        #expect(calls.map(\.terms) == [["Homebrew", "gitleaks"]])
        #expect(calls.map(\.focus) == [["Homeroot"]])
        #expect(calls.map(\.language) == [.german])
        // Whisper hears the same recording Parakeet heard.
        #expect(calls.map(\.samples) == [await transcriber.lastAudio?.samples.count ?? -1])
    }

    @Test func ctrlOptOPutsTheUncheckedRuleTextBack() async {
        let focus = FakeFocusSource()
        focus.queue(emptyField)
        let controller = makeController(
            transcriber: unsure(), opinion: RecordingSecondOpinion(.answer(homebrew)), focus: focus)
        await dictate(controller, app: textEdit)
        let range = TextRange(location: 0, length: homebrew.utf16.count)
        focus.setText(homebrew, at: range)
        #expect(await controller.canReplaceWithRuleText)
        await controller.replaceWithRuleText()
        #expect(keystrokes.pasted == [homebrew, homeroot])
        #expect(focus.selections == [range])
        #expect(await controller.state == .ruleText(.pasted))
        #expect(await controller.lastText == homeroot)
    }

    @Test func uncheckedDictationOffersNoRuleText() async {
        // Whisper heard the same word: nothing replaced, so ⌃⌥O has nothing to put back.
        let controller = makeController(transcriber: unsure(), opinion: RecordingSecondOpinion(.answer(homeroot)))
        await dictate(controller)
        #expect(keystrokes.pasted == [homeroot])
        #expect(await !controller.canReplaceWithRuleText)
    }

    @Test func escDuringTheCheckInsertsNothing() async {
        let opinion = RecordingSecondOpinion(.held(homebrew))
        let controller = makeController(transcriber: unsure(), opinion: opinion)
        let done = Task { await dictate(controller) }
        #expect(await eventually { await !opinion.calls.isEmpty })
        await controller.abort()
        // The check is not waited for: Esc ends the dictation while Whisper still decodes.
        await done.value
        #expect(await controller.state == .notice(.cancelled))
        #expect(keystrokes.pasted.isEmpty)
        #expect(await controller.lastText == homeroot)
        await opinion.release()
    }

    @Test func withoutSecondOpinionNothingChanges() async {
        let controller = makeController(transcriber: unsure(), opinion: nil)
        let log = StateLog(controller)
        await dictate(controller)
        #expect(keystrokes.pasted == [homeroot])
        #expect(await eventually { log.all.last == .inserted(.pasted) })
        #expect(!log.all.contains(.cleaning))
        #expect(await !controller.canReplaceWithRuleText)
    }

    @Test func retryChecksAgain() async {
        let opinion = RecordingSecondOpinion(.answer(homebrew))
        let transcriber = unsure()
        await transcriber.respond(with: .failure(.engineUnavailable("test")))
        let controller = makeController(transcriber: transcriber, opinion: opinion)
        await dictate(controller)
        #expect(await controller.state == .failed(.recognitionFailed))
        #expect(await opinion.calls.isEmpty)
        await transcriber.respond(with: .success(homeroot))
        await controller.retry()
        #expect(await controller.state == .inserted(.pasted))
        #expect(keystrokes.pasted == [homebrew])
        #expect(await opinion.calls.map(\.samples) == [await transcriber.lastAudio?.samples.count ?? -1])
    }
}
