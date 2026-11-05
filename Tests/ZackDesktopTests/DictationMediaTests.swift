import CoreFoundation
import Testing
import ZackCore

@testable import ZackDesktop

/// Playback pause in the dictation flow: paused once the pill shows, resumed however the recording ends. As in
/// `DictationControllerTests`, only the system interfaces are fakes.
@MainActor
struct DictationMediaTests {
    /// The ways a recording ends after its pill appeared.
    enum RecordingEnd: CaseIterable {
        case release, cancel, timeLimit, disconnect, startFailure, passwordField, nothingHeard, shortHold
    }

    let input = FakeAudioInput()
    let clock = TestClock()
    let clipboard = FakeClipboard()
    let keystrokes: FakeKeystrokes
    let capture: MicrophoneCapture
    let commands = FakePlaybackCommands()
    let outputs = FakeAudioOutputs(["com.spotify.client"])
    let media: MediaPause
    /// The setting "Wiedergabe beim Diktieren pausieren".
    let pausePlayback = TestValue(true)
    let field = FocusElement(pid: 42, reference: "field-1" as CFString)

    init() {
        keystrokes = FakeKeystrokes(clipboard: clipboard)
        capture = MicrophoneCapture(input: input)
        media = MediaPause(commands: commands, outputs: outputs, minimumPause: .zero, exitGrace: .zero)
    }

    func makeController(
        modelReady: Bool = true, focus: FakeFocusSource? = nil, media: MediaPause? = nil
    ) -> DictationController<TestClock> {
        let inserter = Inserter(
            clipboard: clipboard, keystrokes: keystrokes, canPostKeystrokes: { true }, sleep: { _ in })
        let pausePlayback = pausePlayback
        return DictationController(
            capture: capture, transcriber: FakeTranscriber("Hallo Welt."), inserter: inserter, clock: clock,
            makeProcessor: { TextProcessor(cleaner: nil) }, modelReady: { modelReady }, microphoneAllowed: { true },
            focus: focus, media: media ?? self.media, pausePlayback: { pausePlayback.current })
    }

    /// One second of speech, then the key comes up.
    func speakAndRelease(_ controller: DictationController<TestClock>) async {
        input.push(tone())
        clock.advance(by: .seconds(1))
        await controller.finish()
    }

    @Test func tapBeforeThePillNeverPauses() async {
        let controller = makeController()
        await controller.begin()
        capture.waitForControl()
        await controller.cancel()
        media.drain()
        #expect(commands.calls.isEmpty)
        #expect(outputs.reads == 0)
    }

    @Test(arguments: RecordingEnd.allCases)
    func everyEndOfTheRecordingResumesOnce(_ end: RecordingEnd) async {
        let focus = end == .passwordField ? FakeFocusSource() : nil
        focus?.holdNextRead()
        let gate = end == .startFailure ? input.blockNextStart() : nil
        if end == .startFailure { input.failStarts(with: .audioFormat) }
        let controller = makeController(focus: focus)
        await controller.begin()
        // A blocked start would block this wait as well.
        if end != .startFailure { capture.waitForControl() }
        await controller.confirm()
        media.drain()
        #expect(commands.calls == [.pause])
        let expected: DictationState
        switch end {
        case .release:
            await speakAndRelease(controller)
            expected = .inserted(.pasted)
        case .cancel:
            await controller.cancel()
            expected = .idle
        case .timeLimit:
            input.push(tone())
            #expect(await eventually { clock.sleeperCount == 1 })
            clock.advance(by: .seconds(181))
            expected = .inserted(.pasted)
        case .disconnect:
            input.push(tone())
            input.emit(.deviceLost)
            expected = .failed(.microphoneDisconnected)
        case .startFailure:
            gate?.open()
            expected = .failed(.microphoneUnavailable)
        case .passwordField:
            #expect(await eventually { focus?.heldReads == 1 })
            focus?.releaseHeldRead(returning: FocusSnapshot(element: field, isSecure: true))
            expected = .failed(.passwordField)
        case .nothingHeard:
            input.push(Array(repeating: 0, count: 16_000))
            clock.advance(by: .seconds(1))
            await controller.finish()
            expected = .failed(.nothingHeard)
        case .shortHold:
            input.push(tone(seconds: 0.2))
            clock.advance(by: .milliseconds(250))
            await controller.finish()
            expected = .idle
        }
        #expect(await eventually { await controller.state == expected })
        media.drain()
        #expect(commands.calls == [.pause, .play])
    }

    /// A hold just past the pill: pause and play would follow each other within milliseconds, and Spotify ignores
    /// a play that close to a pause. The play waits until the pause has settled.
    @Test func shortHoldResumesOnlyOnceThePauseSettled() async {
        let settling = MediaPause(
            commands: commands, outputs: outputs, minimumPause: .milliseconds(200), exitGrace: .zero)
        let controller = makeController(media: settling)
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        input.push(tone(seconds: 0.2))
        clock.advance(by: .milliseconds(250))
        await controller.finish()
        #expect(await controller.state == .idle)
        settling.drain()
        #expect(commands.calls == [.pause, .play])
        #expect((commands.pauseToPlay ?? .zero) >= .milliseconds(200))
    }

    /// The pill shows a known failure (here the model is missing): nothing records, so nothing pauses.
    @Test func knownFailureAtThePillDoesNotPause() async {
        let controller = makeController(modelReady: false)
        await controller.begin()
        await controller.confirm()
        #expect(await controller.state == .failed(.modelMissing))
        media.drain()
        #expect(commands.calls.isEmpty)
        #expect(outputs.reads == 0)
    }

    @Test func settingOffDoesNotPause() async {
        pausePlayback.set(false)
        let controller = makeController()
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        await speakAndRelease(controller)
        #expect(await controller.state == .inserted(.pasted))
        media.drain()
        #expect(commands.calls.isEmpty)
        #expect(outputs.reads == 0)
    }

    /// The setting is read when the pill appears; the running dictation still resumes what it paused.
    @Test func switchingOffDuringADictationStillResumes() async {
        let controller = makeController()
        await controller.begin()
        capture.waitForControl()
        await controller.confirm()
        media.drain()
        #expect(commands.calls == [.pause])
        pausePlayback.set(false)
        await speakAndRelease(controller)
        #expect(await controller.state == .inserted(.pasted))
        media.drain()
        #expect(commands.calls == [.pause, .play])
    }
}
