import Foundation
import OSLog
import Synchronization
import ZackCore
import ZackWhisper

/// The second opinion as the service loads and unloads it.
public protocol TermCheckEngine: SecondOpinion {
    func prepare() async throws
    func warmUp() async throws
    /// A running `recognize` ends normally.
    func unload() async
}

extension WhisperEngine: TermCheckEngine {}

/// What the switch "Fachbegriffe gegenprüfen" shows.
public enum TermCheckState: Equatable, Sendable {
    case off
    case downloading(Double)
    case loading
    case ready
    case failed(TermCheckFailure)
}

/// Why the switch turned itself off.
public enum TermCheckFailure: Equatable, Sendable {
    /// The model is absent or incomplete at app start; turning the switch on loads it.
    case missing
    case download
    /// The model differs from the checked version and was deleted.
    case unverified
    case load
}

/// Thread-safe holder the processor factory reads per dictation; holds the engine only while the check is ready.
public final class SecondOpinionSlot: Sendable {
    private let value = Mutex<(any SecondOpinion)?>(nil)

    public init() {}

    public var current: (any SecondOpinion)? { value.withLock { $0 } }

    func set(_ opinion: (any SecondOpinion)?) {
        value.withLock { $0 = opinion }
    }
}

/// Downloads, checks, loads and unloads Whisper behind the setting. Downloads only on `enable`, never on `start`.
@MainActor public final class TermCheckService {
    public private(set) var state: TermCheckState = .off {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    public var onStateChange: ((TermCheckState) -> Void)?
    public let slot = SecondOpinionSlot()

    private let settings: Settings
    private let setup: WhisperSetup
    private let engine: any TermCheckEngine
    private let logger = Logger(subsystem: Signposts.subsystem, category: "term-check")
    /// The newest run; every new run waits for it, so an unload never overtakes a later load.
    private var work: Task<Void, Never>?
    /// Bumped by every run and by `disable`; a run whose number is outdated touches nothing.
    private var generation = 0

    public init(settings: Settings, setup: WhisperSetup, engine: any TermCheckEngine) {
        self.settings = settings
        self.setup = setup
        self.engine = engine
    }

    /// The app imports no ZackWhisper: model and engine both live in the models directory.
    public static func standard(settings: Settings) throws -> TermCheckService {
        let setup = try WhisperSetup.standard()
        return TermCheckService(settings: settings, setup: setup, engine: WhisperEngine(base: setup.modelsDirectory))
    }

    /// App launch, after Parakeet: with the switch on, checks and loads the model on disk; a missing or incomplete
    /// model turns the switch off instead of downloading.
    public func start() {
        guard settings.termCheck, state == .off else { return }
        guard setup.status() == .ready else {
            fail(.missing)
            return
        }
        run(download: false)
    }

    /// The user turned the switch on: downloads a missing model, then checks and loads it.
    public func enable() {
        settings.termCheck = true
        switch state {
        case .downloading, .loading, .ready: return
        case .off, .failed: run(download: setup.status() != .ready)
        }
    }

    /// The user turned the switch off: cancels a download, clears the slot and unloads after any running load.
    /// A dictation that already took the engine finishes its check.
    public func disable() {
        settings.termCheck = false
        generation += 1
        slot.set(nil)
        state = .off
        let previous = work
        previous?.cancel()
        let engine = engine
        work = Task {
            await previous?.value
            await engine.unload()
        }
    }

    private func run(download: Bool) {
        generation += 1
        let current = generation
        state = download ? .downloading(0) : .loading
        let previous = work
        work = Task {
            await previous?.value
            await load(download: download, generation: current)
        }
    }

    private func load(download: Bool, generation current: Int) async {
        // Turned off while it waited for the previous run: no download, no verify with the switch off.
        guard generation == current, !Task.isCancelled else { return }
        let clock = ContinuousClock()
        let checkStart = clock.now
        do {
            if download {
                try await setup.download { [weak self] fraction in
                    Task { @MainActor in self?.progress(fraction, generation: current) }
                }
            } else {
                try await setup.verify()
            }
        } catch {
            guard generation == current else { return }
            logger.error("term check model: \(String(describing: type(of: error)), privacy: .public)")
            fail(Self.isUnverified(error) ? .unverified : download ? .download : .load)
            return
        }
        guard generation == current else { return }
        let checked = clock.now - checkStart
        state = .loading
        let loadStart = clock.now
        do {
            try await engine.prepare()
            guard generation == current else { return }
            try await engine.warmUp()
        } catch {
            await engine.unload()
            guard generation == current else { return }
            logger.error("term check load: \(String(describing: type(of: error)), privacy: .public)")
            fail(.load)
            return
        }
        guard generation == current else { return }
        let loaded = clock.now - loadStart
        logger.info(
            "term check ready: \(download ? "download" : "verify", privacy: .public) \(Self.milliseconds(checked), privacy: .public) ms, load \(Self.milliseconds(loaded), privacy: .public) ms"
        )
        slot.set(engine)
        state = .ready
    }

    /// Progress arrives on any queue and may trail the download's end; only a growing value during it counts.
    private func progress(_ fraction: Double, generation current: Int) {
        guard generation == current, case .downloading(let shown) = state, fraction >= shown + 0.01 || fraction >= 1,
            fraction > shown
        else { return }
        state = .downloading(min(fraction, 1))
    }

    private func fail(_ reason: TermCheckFailure) {
        settings.termCheck = false
        slot.set(nil)
        state = .failed(reason)
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration / .milliseconds(1))
    }

    private static func isUnverified(_ error: any Error) -> Bool {
        if case .modelUnverified? = error as? ZackError { return true }
        return false
    }
}
