import Testing

@testable import ZackDesktop

struct AppStatusTests {
    func evaluate(
        model: ModelStatus = .ready, loaded: Bool = true, microphone: PermissionState = .granted,
        accessibility: Bool = true, inputMonitoring: Bool? = nil, dictation: DictationState = .idle
    ) -> AppStatus {
        AppStatus.evaluate(
            model: model, modelLoaded: loaded, microphone: microphone, accessibility: accessibility,
            inputMonitoring: inputMonitoring, dictation: dictation)
    }

    @Test func readyWhenEverythingIsThere() {
        #expect(evaluate() == .ready)
        #expect(AppStatus.ready.title(hotkey: .fn) == "Bereit · fn halten")
        #expect(AppStatus.ready.title(hotkey: .rightOption) == "Bereit · rechte ⌥ halten")
    }

    @Test func missingPartsTurnYellow() {
        #expect(evaluate(model: .adoptable) == .modelMissing)
        #expect(evaluate(microphone: .denied) == .permissionMissing)
        #expect(evaluate(accessibility: false) == .permissionMissing)
        #expect(evaluate(inputMonitoring: false) == .permissionMissing)
        #expect(evaluate(inputMonitoring: true) == .ready)
        #expect(AppStatus.modelMissing.tone == .yellow)
        #expect(AppStatus.permissionMissing.opensSetup)
    }

    @Test func recordingAndLoading() {
        #expect(evaluate(dictation: .recording(elapsed: .zero, level: 0)) == .recording)
        #expect(evaluate(loaded: false) == .loading)
        #expect(AppStatus.recording.tone == .blue)
    }
}
