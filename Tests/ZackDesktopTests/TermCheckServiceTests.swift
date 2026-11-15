import Foundation
import Testing
import ZackCore
import ZackTestSupport
import ZackWhisper

@testable import ZackDesktop

/// Records the service's calls; `prepare` can fail or wait for `releasePrepare`, `recognize` goes to `opinion`.
actor FakeTermCheckEngine: TermCheckEngine {
    enum Event: Equatable { case prepare, warmUp, unload }

    nonisolated let id = "fake-whisper"
    nonisolated let opinion: RecordingSecondOpinion
    private(set) var events: [Event] = []
    private let prepareFailure: ZackError?
    private var holdPrepare: Bool
    private var prepareWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        prepareFailure: ZackError? = nil, holdPrepare: Bool = false,
        opinion: RecordingSecondOpinion = RecordingSecondOpinion(.answer(""))
    ) {
        self.prepareFailure = prepareFailure
        self.holdPrepare = holdPrepare
        self.opinion = opinion
    }

    func prepare() async throws {
        events.append(.prepare)
        if holdPrepare { await withCheckedContinuation { prepareWaiters.append($0) } }
        if let prepareFailure { throw prepareFailure }
    }

    func releasePrepare() {
        holdPrepare = false
        for waiter in prepareWaiters { waiter.resume() }
        prepareWaiters = []
    }

    func warmUp() async throws { events.append(.warmUp) }
    func unload() async { events.append(.unload) }

    func recognize(_ audio: AudioClip, terms: [String], focus: [String], language: DictationLanguage)
        async throws -> String
    {
        try await opinion.recognize(audio, terms: terms, focus: focus, language: language)
    }
}

@MainActor
final class StateRecorder {
    var states: [TermCheckState] = []

    /// The cases in order, repeats folded: progress steps are not pinned, their hop to the main actor may merge them.
    var kinds: [String] {
        states.map { state -> String in
            switch state {
            case .off: "off"
            case .downloading: "downloading"
            case .loading: "loading"
            case .ready: "ready"
            case .failed: "failed"
            }
        }.reduce(into: []) { if $0.last != $1 { $0.append($1) } }
    }
}

@MainActor
@Suite(.serialized)
struct TermCheckServiceTests {
    /// One fixed suite name, as in `SettingsTests`; serialized tests clear it afterwards.
    nonisolated static let suiteName = "com.netclusive.zack.tests.termcheck"

    enum Download { case writes, fails, hangs }

    struct Fixture {
        let models: URL
        let settings: Settings
        let engine: FakeTermCheckEngine
        let service: TermCheckService
        let recorder: StateRecorder
        let downloads: Counter
        let cancellations: Counter
        let verifications: Counter

        func cleanup() {
            UserDefaults(suiteName: TermCheckServiceTests.suiteName)?
                .removePersistentDomain(forName: TermCheckServiceTests.suiteName)
            try? FileManager.default.removeItem(at: models)
        }
    }

    func makeFixture(
        download: Download = .writes, verified: Bool = true, engine: FakeTermCheckEngine = FakeTermCheckEngine(),
        modelPresent: Bool = false, settingOn: Bool = false
    ) throws -> Fixture {
        let models = FileManager.default.temporaryDirectory.appending(path: "zack-termcheck-\(UUID().uuidString)")
        let defaults = try #require(UserDefaults(suiteName: Self.suiteName))
        defaults.removePersistentDomain(forName: Self.suiteName)
        let settings = Settings(defaults: defaults)
        settings.termCheck = settingOn
        if modelPresent { try WhisperFakeModel.write(in: models) }
        let downloads = Counter()
        let cancellations = Counter()
        let verifications = Counter()
        let setup = WhisperSetup(
            modelsDirectory: models,
            downloader: { base, progress in
                downloads.increment()
                switch download {
                case .writes:
                    try WhisperFakeModel.write(in: base)
                    progress(0.5)
                    progress(1)
                case .fails:
                    throw URLError(.notConnectedToInternet)
                case .hangs:
                    do {
                        try await Task.sleep(for: .seconds(3600))
                    } catch {
                        cancellations.increment()
                        throw error
                    }
                }
            },
            verifier: { _ in
                verifications.increment()
                if !verified { throw ZackError.modelUnverified("config.json") }
            })
        let service = TermCheckService(settings: settings, setup: setup, engine: engine)
        let recorder = StateRecorder()
        service.onStateChange = { recorder.states.append($0) }
        return Fixture(
            models: models, settings: settings, engine: engine, service: service, recorder: recorder,
            downloads: downloads, cancellations: cancellations, verifications: verifications)
    }

    /// Long enough for any stray task to run; the fakes answer at once.
    func settle() async {
        try? await Task.sleep(for: .milliseconds(100))
    }

    // Enable

    @Test func enableWithoutModelDownloadsLoadsAndFillsTheSlot() async throws {
        let f = try makeFixture()
        defer { f.cleanup() }
        f.service.enable()
        #expect(f.settings.termCheck)
        #expect(await eventually { await f.service.state == .ready })
        #expect(f.recorder.kinds == ["downloading", "loading", "ready"])
        #expect(f.downloads.value == 1)
        #expect(f.service.slot.current != nil)
        #expect(await f.engine.events == [.prepare, .warmUp])
    }

    @Test func enableWithModelSkipsTheDownload() async throws {
        let f = try makeFixture(modelPresent: true)
        defer { f.cleanup() }
        f.service.enable()
        #expect(await eventually { await f.service.state == .ready })
        #expect(f.recorder.kinds == ["loading", "ready"])
        #expect(f.downloads.value == 0)
        // The copy on disk is checked before every load.
        #expect(f.verifications.value == 1)
        #expect(f.service.slot.current != nil)
    }

    @Test func failedDownloadTurnsTheSettingOff() async throws {
        let f = try makeFixture(download: .fails)
        defer { f.cleanup() }
        f.service.enable()
        #expect(await eventually { await f.service.state == .failed(.download) })
        #expect(!f.settings.termCheck)
        #expect(f.service.slot.current == nil)
        #expect(await f.engine.events.isEmpty)
    }

    @Test func unverifiedDownloadTurnsTheSettingOff() async throws {
        let f = try makeFixture(verified: false)
        defer { f.cleanup() }
        f.service.enable()
        #expect(await eventually { await f.service.state == .failed(.unverified) })
        #expect(!f.settings.termCheck)
        #expect(f.service.slot.current == nil)
        #expect(!WhisperFakeModel.exists(in: f.models))
        #expect(await f.engine.events.isEmpty)
    }

    @Test func failedLoadTurnsTheSettingOff() async throws {
        let engine = FakeTermCheckEngine(prepareFailure: .engineUnavailable("x"))
        let f = try makeFixture(engine: engine, modelPresent: true)
        defer { f.cleanup() }
        f.service.enable()
        #expect(await eventually { await f.service.state == .failed(.load) })
        #expect(!f.settings.termCheck)
        #expect(f.service.slot.current == nil)
        #expect(await f.engine.events == [.prepare, .unload])
    }

    // Disable

    @Test func disableDuringDownloadCancelsIt() async throws {
        let f = try makeFixture(download: .hangs)
        defer { f.cleanup() }
        f.service.enable()
        #expect(await eventually { f.downloads.value == 1 })
        f.service.disable()
        #expect(f.service.state == .off)
        #expect(!f.settings.termCheck)
        #expect(await eventually { f.cancellations.value == 1 })
        await settle()
        // A cancelled download is not a failed one.
        #expect(f.service.state == .off)
        #expect(!f.recorder.kinds.contains("failed"))
        #expect(await f.engine.events.allSatisfy { $0 == .unload })
    }

    @Test func disableUnloadsAndClearsTheSlot() async throws {
        let f = try makeFixture(modelPresent: true)
        defer { f.cleanup() }
        f.service.enable()
        #expect(await eventually { await f.service.state == .ready })
        f.service.disable()
        #expect(f.service.state == .off)
        #expect(f.service.slot.current == nil)
        #expect(!f.settings.termCheck)
        #expect(await eventually { await f.engine.events == [.prepare, .warmUp, .unload] })
    }

    @Test(.timeLimit(.minutes(1))) func disableDuringARunningCheckLetsItEnd() async throws {
        let opinion = RecordingSecondOpinion(.held("Über Homebrew ziehe ich gitleaks."))
        let f = try makeFixture(engine: FakeTermCheckEngine(opinion: opinion), modelPresent: true)
        defer { f.cleanup() }
        f.service.enable()
        #expect(await eventually { await f.service.state == .ready })
        // As a dictation does: the processor took the engine from the slot before the switch went off.
        let engine = try #require(f.service.slot.current)
        let clip = AudioClip(samples: tone(), sampleRate: 16_000)
        let check = Task {
            try await engine.recognize(clip, terms: ["Homebrew"], focus: ["Homeroot"], language: .german)
        }
        await opinion.waitForCall()
        f.service.disable()
        #expect(f.service.slot.current == nil)
        await opinion.release()
        #expect(try await check.value == "Über Homebrew ziehe ich gitleaks.")
        #expect(f.service.state == .off)
    }

    @Test func disableDuringLoadUnloadsAfterTheLoad() async throws {
        let engine = FakeTermCheckEngine(holdPrepare: true)
        let f = try makeFixture(engine: engine, modelPresent: true)
        defer { f.cleanup() }
        f.service.enable()
        #expect(await eventually { await engine.events == [.prepare] })
        f.service.disable()
        #expect(f.service.state == .off)
        await engine.releasePrepare()
        // The load finished after the switch went off; the engine is unloaded after it, not before.
        #expect(await eventually { await engine.events == [.prepare, .unload] })
        await settle()
        #expect(f.service.state == .off)
        #expect(f.service.slot.current == nil)
        #expect(await engine.events == [.prepare, .unload])
    }

    @Test func disableThenEnableEndsReady() async throws {
        let engine = FakeTermCheckEngine(holdPrepare: true)
        let f = try makeFixture(engine: engine, modelPresent: true)
        defer { f.cleanup() }
        f.service.enable()
        #expect(await eventually { await engine.events == [.prepare] })
        f.service.disable()
        f.service.enable()
        await engine.releasePrepare()
        #expect(await eventually { await f.service.state == .ready })
        // The unload of the switch-off runs before the new load, never after it.
        #expect(await engine.events == [.prepare, .unload, .prepare, .warmUp])
        #expect(f.service.slot.current != nil)
        #expect(f.settings.termCheck)
    }

    // App start

    @Test func startWithModelLoadsAndFillsTheSlot() async throws {
        let f = try makeFixture(modelPresent: true, settingOn: true)
        defer { f.cleanup() }
        f.service.start()
        #expect(await eventually { await f.service.state == .ready })
        #expect(f.recorder.kinds == ["loading", "ready"])
        #expect(f.downloads.value == 0)
        #expect(f.service.slot.current != nil)
    }

    @Test func startWithIncompleteModelTurnsOffWithoutDownload() async throws {
        let f = try makeFixture(modelPresent: true, settingOn: true)
        defer { f.cleanup() }
        // Left by an interrupted download.
        try FileManager.default.removeItem(
            at: WhisperModelStore.tokenizerFolder(in: f.models).appending(path: "tokenizer.json"))
        f.service.start()
        #expect(f.service.state == .failed(.missing))
        #expect(!f.settings.termCheck)
        await settle()
        #expect(f.downloads.value == 0)
        #expect(await f.engine.events.isEmpty)
    }

    @Test func startWithChangedModelDeletesItAndTurnsOff() async throws {
        let f = try makeFixture(verified: false, modelPresent: true, settingOn: true)
        defer { f.cleanup() }
        f.service.start()
        #expect(await eventually { await f.service.state == .failed(.unverified) })
        #expect(!f.settings.termCheck)
        #expect(!WhisperFakeModel.exists(in: f.models))
        #expect(f.downloads.value == 0)
        #expect(await f.engine.events.isEmpty)
    }

    @Test func startWithSettingOffDoesNothing() async throws {
        let f = try makeFixture(modelPresent: true)
        defer { f.cleanup() }
        f.service.start()
        await settle()
        #expect(f.service.state == .off)
        #expect(f.recorder.states.isEmpty)
        #expect(f.downloads.value == 0)
        #expect(f.verifications.value == 0)
        #expect(await f.engine.events.isEmpty)
    }
}
