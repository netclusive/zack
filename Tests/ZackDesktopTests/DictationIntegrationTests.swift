import Foundation
import Testing
import ZackCore
import ZackParakeet
import ZackTestSupport

@testable import ZackDesktop

/// The dictation flow with the real model the app uses (`localOnly` from `~/Library/Application Support/Zack/Models`).
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ZACK_INTEGRATION"] == "1"), .serialized)
@MainActor
struct DictationIntegrationTests {
    @Test func dictationWithParakeetUltra() async throws {
        // No silent download: the app's model must already be there (setup window, "Übernehmen").
        let models = try ModelStorage.directory(createIfNeeded: false)
        try #require(ParakeetModelStore.isComplete(.ultra, in: models), "Parakeet Ultra fehlt in \(models.path)")
        let input = FakeAudioInput()
        let clipboard = FakeClipboard()
        let keystrokes = FakeKeystrokes(clipboard: clipboard)
        let inserter = Inserter(
            clipboard: clipboard, keystrokes: keystrokes, canPostKeystrokes: { true }, sleep: { _ in })
        let clock = TestClock()
        let controller = DictationController(
            capture: MicrophoneCapture(input: input),
            transcriber: ParakeetTranscriber(variant: .ultra, policy: .localOnly), inserter: inserter,
            clock: clock, makeProcessor: { TextProcessor() }, modelReady: { true },
            microphoneAllowed: { true })
        await controller.begin()
        await controller.confirm()
        let clip = try Fixture.hallo()
        input.push(clip.samples)
        // Held as long as the recording lasts; under 0.3 s the dictation would end silently.
        clock.advance(by: .seconds(clip.duration))
        await controller.finish()
        #expect(await controller.state == .inserted(.pasted))
        let text = try #require(keystrokes.pasted.first)
        #expect(text.localizedCaseInsensitiveContains("Test"), "\(text)")
    }
}
