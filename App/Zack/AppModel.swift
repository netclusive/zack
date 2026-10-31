import AppKit
import CoreAudio
import Observation
import Synchronization
import ZackApple
import ZackCore
import ZackDesktop
import ZackParakeet
import ZackUpdate
import os

/// Thread-safe flag the dictation actor reads without hopping to the main actor.
final class Flag: Sendable {
    private let value = Atomic<Bool>(false)

    var isSet: Bool { value.load(ordering: .relaxed) }

    func set(_ newValue: Bool) {
        value.store(newValue, ordering: .relaxed)
    }
}

/// The menu entry for code mode: the last active app other than Zack and how `code-apps.txt` lists it.
struct CodeModeMenuItem: Equatable {
    let name: String
    let bundleID: String
    let match: CodeApps.Match
}

/// Connects settings, permissions, model, hotkey, dictation and the windows. The views only read it.
@MainActor
@Observable
final class AppModel {
    private(set) var hotkey: HotkeyKey
    private(set) var aiCleanup: Bool
    private(set) var microphoneReadiness: MicrophoneReadiness
    private(set) var launchAtLogin = false
    private(set) var dictation = DictationState.idle
    private(set) var modelStatus = ModelStatus.missing
    private(set) var modelLoaded = false
    /// Loading the model on disk failed; no automatic retry until the setup asks for one.
    private(set) var modelLoadFailed = false
    private(set) var microphone = PermissionState.notDetermined
    private(set) var accessibility = false
    private(set) var inputMonitoring = false
    private(set) var cleanerAvailability = CleanerAvailability.notReady
    private(set) var microphoneMenu = MicrophoneMenu(saved: nil, devices: [], defaultID: nil, selectionFailed: false)
    private(set) var downloadProgress: Double?
    private(set) var setupError: String?
    private(set) var canRetry = false
    private(set) var hasLastText = false
    /// ⌃⌥O has an AI-cleaned dictation to replace.
    private(set) var canReplaceWithRuleText = false
    private(set) var codeModeApp: CodeModeMenuItem?
    /// Shortcuts another app already holds; they stay unregistered.
    private(set) var shortcutTaken: Set<Shortcut> = []
    /// Menu line while another app has Secure Input on, read when the menu opens.
    private(set) var secureInputLine: String?
    /// The pane the settings window shows; kept while the app runs, so the next opening returns to it.
    private(set) var settingsPane = SettingsPane.general

    /// Set by `AppDelegate` right after creating both; the updates pane reads it.
    @ObservationIgnored var updater: Updater?
    /// Created in `start()`; nil without user files. The panes observe the editors themselves.
    @ObservationIgnored private(set) var vocabularyEditor: FileEditor<VocabularyFormat>?
    @ObservationIgnored private(set) var snippetsEditor: FileEditor<SnippetFormat>?
    @ObservationIgnored private(set) var codeAppsEditor: FileEditor<CodeAppsFormat>?

    @ObservationIgnored private let settings = Settings()
    @ObservationIgnored private let signposts = Signposts()
    @ObservationIgnored private let transcriber = ParakeetTranscriber(variant: .ultra, policy: .localOnly)
    @ObservationIgnored private let cleaner = AppleFoundationCleaner()
    @ObservationIgnored private let input: EngineAudioInput
    @ObservationIgnored private let capture: MicrophoneCapture
    @ObservationIgnored private let modelReady = Flag()
    @ObservationIgnored private let modelSetup = try? ModelSetup.standard()
    @ObservationIgnored private let files = try? UserFiles.standard()
    @ObservationIgnored private let windows = WindowPresenter()
    @ObservationIgnored private let logger = Logger(subsystem: Signposts.subsystem, category: "app")
    @ObservationIgnored private var inserter: Inserter!
    @ObservationIgnored private var controller: DictationController<ContinuousClock>!
    @ObservationIgnored private var hotkeyMonitor: HotkeyMonitor?
    @ObservationIgnored private var shortcuts: CarbonShortcuts?
    /// Esc is registered for the running recognition; if not, `onInput` reads it along and the app in front gets it too.
    @ObservationIgnored private var escapeRegistered = false
    @ObservationIgnored private let focus = AXFocusSource()
    @ObservationIgnored private let memory = CursorMemory()
    @ObservationIgnored private var lastActive: (name: String, bundleID: String)?
    @ObservationIgnored private var activationObservation: (any NSObjectProtocol)?
    @ObservationIgnored private var actions: AsyncStream<(HotkeyAction, FrontApp?)>.Continuation?
    @ObservationIgnored private var pill: PillPanelController?
    @ObservationIgnored private var inputObservation: AudioPropertyObservation?
    @ObservationIgnored private var deviceListObservation: AudioPropertyObservation?
    @ObservationIgnored private var inputTarget: AudioObjectID?
    @ObservationIgnored private var menuObservation: (any NSObjectProtocol)?
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var setupPolling: Task<Void, Never>?

    init() {
        hotkey = settings.hotkey
        aiCleanup = settings.aiCleanup
        microphoneReadiness = settings.microphoneReadiness
        let settings = settings
        // Runs on the capture's control queue and on AVAudioEngine's notification queue:
        // only settings and static reads.
        input = EngineAudioInput(device: {
            MicrophoneChoice.resolve(settings.microphone, in: AudioDevices.inputDevices())
                .deviceID(default: AudioDevices.defaultInputID())
        })
        capture = MicrophoneCapture(input: input)
        inserter = makeInserter(timing: .measured)
        let files = files
        let cleaner = cleaner
        let modelReady = modelReady
        let memory = memory
        controller = DictationController(
            capture: capture, transcriber: transcriber, inserter: inserter, clock: ContinuousClock(),
            makeProcessor: {
                let loaded = files?.load() ?? (vocabulary: Vocabulary(), snippets: [])
                let useCleaner = settings.aiCleanup && AppleFoundationCleaner.availability == .available
                return TextProcessor(
                    vocabulary: loaded.vocabulary, snippets: loaded.snippets, cleaner: useCleaner ? cleaner : nil)
            },
            modelReady: { modelReady.isSet },
            microphoneAllowed: { Permissions.microphone() == .granted },
            signposts: signposts, readiness: { settings.microphoneReadiness },
            focus: focus, memory: memory,
            // Read per dictation, on the controller actor.
            codeMode: { files?.loadCodeApps().mode(for: $0) ?? .prose })
    }

    /// A model that failed to load counts as missing: yellow, and a click opens the setup.
    var status: AppStatus {
        AppStatus.evaluate(
            model: modelLoadFailed ? .missing : modelStatus, modelLoaded: modelLoaded, microphone: microphone,
            accessibility: accessibility, inputMonitoring: Permissions.needsInputMonitoring ? inputMonitoring : nil,
            dictation: dictation)
    }

    /// Status line and menu bar label; `AppStatus` has no case for a failed load, so its title is set here.
    var statusTitle: String {
        status == .modelMissing && modelLoadFailed
            ? "Modell konnte nicht geladen werden" : status.title(hotkey: hotkey)
    }

    var cleanerAvailable: Bool { cleanerAvailability == .available }

    /// Why the AI toggle is greyed out; nil if Apple Intelligence is available.
    var cleanerHint: String? {
        switch cleanerAvailability {
        case .available: nil
        case .notEnabled: "Apple Intelligence ist ausgeschaltet (Systemeinstellungen)."
        case .deviceNotEligible: "Apple Intelligence ist auf diesem Mac nicht verfügbar."
        case .notReady: "Das Apple-Modell wird noch geladen."
        }
    }

    func start() {
        do {
            try files?.createMissing()
        } catch {
            logger.error("user files: \(String(describing: type(of: error)), privacy: .public)")
        }
        if let files {
            vocabularyEditor = FileEditor(files: files, kind: .vocabulary)
            snippetsEditor = FileEditor(files: files, kind: .snippets)
            codeAppsEditor = FileEditor(files: files, kind: .codeApps)
        }
        pill = PillPanelController(signposts: signposts) { [weak self] in self?.showSetup() }
        pill?.prepare()
        startHotkey()
        startShortcuts()
        observeDictation()
        // Seed the target so the first device event does not reopen an unchanged input.
        inputTarget = resolveInputTarget()
        // Handlers run on the main queue. A warm, idle input moves to the new device;
        // a running recording keeps its device.
        inputObservation = AudioDevices.observeDefaultInput { [weak self] in
            MainActor.assumeIsolated { self?.inputMayHaveChanged() }
        }
        deviceListObservation = AudioDevices.observeDeviceList { [weak self] in
            MainActor.assumeIsolated { self?.inputMayHaveChanged() }
        }
        // Permissions change without a notification; one check per menu opening keeps the status line current
        // without polling. Whether the menu bar menu posts this is not documented offline; check by hand.
        menuObservation = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            // Delivered on the main queue (`queue: .main`).
            MainActor.assumeIsolated { self?.refresh() }
        }
        observeActivation()
        refresh()
        if status.opensSetup { showSetup() }
    }

    /// Reads permissions, model and Apple Intelligence again; every second while the setup pane is shown.
    func refresh() {
        microphone = Permissions.microphone()
        let trusted = Permissions.accessibility()
        // Monitors added again after the grant see other keys.
        // Restarting the monitors resets the key state: a key held right now loses its release, and that recording ends at the
        // time limit. Unlikely, since the grant happens in System Settings.
        if trusted, !accessibility { hotkeyMonitor?.start() }
        accessibility = trusted
        inputMonitoring = Permissions.inputMonitoring()
        cleanerAvailability = AppleFoundationCleaner.availability
        updateMicrophoneMenu()
        updateCodeModeApp()
        launchAtLogin = LoginItem.isEnabled
        modelStatus = modelSetup?.status() ?? .missing
        // A model that is gone, adopted or downloaded again gets a fresh load.
        if modelStatus != .ready { modelLoadFailed = false }
        // After a failed load, fn shows the setup hint instead of loading again.
        modelReady.set(modelStatus == .ready && !modelLoadFailed)
        loadModelIfReady()
        applyReadiness()
        updateLastDictationActions()
        secureInputLine = SecureInputLine.text(enabled: SecureInput.isEnabled(), holder: SecureInput.holderName())
    }

    // MARK: Menu

    func setHotkey(_ key: HotkeyKey) {
        settings.hotkey = key
        hotkey = key
        hotkeyMonitor?.key = key
    }

    func setAICleanup(_ on: Bool) {
        settings.aiCleanup = on
        aiCleanup = on
    }

    /// Applies at once: "Aus" closes a ready microphone, "Immer" opens it (if permission and model are there).
    func setMicrophoneReadiness(_ readiness: MicrophoneReadiness) {
        settings.microphoneReadiness = readiness
        microphoneReadiness = readiness
        applyReadiness()
    }

    func setMicrophone(_ id: String) {
        settings.microphone = MicrophoneMenu.choice(
            for: id, devices: AudioDevices.inputDevices(), current: settings.microphone)
        inputMayHaveChanged()
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            try LoginItem.setEnabled(on)
        } catch {
            logger.error("login item: \(String(describing: type(of: error)), privacy: .public)")
        }
        if LoginItem.needsApproval { LoginItem.openSystemSettings() }
        launchAtLogin = LoginItem.isEnabled
    }

    func copyLastText() {
        Task {
            if let text = await controller.lastText { inserter.copy(text) }
        }
    }

    /// Reads the app in front here, on the main thread, then inserts the last dictation there.
    func insertLast() {
        let controller = controller!
        Task {
            await Self.keysReleased(.insertLast)
            var app: FrontApp?
            if let front = NSWorkspace.shared.frontmostApplication {
                app = FrontApp(bundleID: front.bundleIdentifier, pid: front.processIdentifier)
            }
            await controller.insertLast(app: app)
        }
    }

    func replaceWithRuleText() {
        let controller = controller!
        Task {
            await Self.keysReleased(.ruleText)
            await controller.replaceWithRuleText()
        }
    }

    /// Up to 2 s for the shortcut's keys to go up; a menu click finds them up at once.
    private static func keysReleased(_ shortcut: Shortcut) async {
        _ = await ShortcutRelease.waitUntilReleased(
            polls: 200, sleep: { try? await Task.sleep(for: .milliseconds(10)) },
            isReleased: { ShortcutRelease.isReleased(shortcut) })
    }

    func retry() {
        Task { await controller.retry() }
    }

    func toggleCodeMode() {
        guard let bundleID = codeModeApp?.bundleID else { return }
        do {
            try files?.toggleCodeMode(for: bundleID)
        } catch {
            logger.error("code apps: \(String(describing: type(of: error)), privacy: .public)")
        }
        // An open code apps pane shows the change at once.
        codeAppsEditor?.reload()
        refresh()
    }

    /// Opens the file in the default text editor, for lines the editors cannot show.
    func openInTextEditor(_ kind: UserFileKind) {
        if let url = files?.url(for: kind) { NSWorkspace.shared.open(url) }
    }

    /// Reads the files again, so changes made elsewhere show when the settings window comes to the front.
    func reloadEditors() {
        vocabularyEditor?.reload()
        snippetsEditor?.reload()
        codeAppsEditor?.reload()
    }

    func statusClicked() {
        if status.opensSetup { showSetup() }
    }

    /// Opens the settings in the setup pane: at launch, after a failed model load, from the pill and the status line.
    func showSetup() {
        showSettings(.setup)
    }

    /// Opens the settings window in `pane`, or in the last chosen one; an open window comes to the front.
    func showSettings(_ pane: SettingsPane? = nil) {
        if let pane { settingsPane = pane }
        refresh()
        windows.show(
            id: Self.settingsWindow, title: settingsPane.title, size: CGSize(width: 720, height: 480),
            minSize: CGSize(width: 640, height: 420), onClose: { [weak self] in self?.stopSetupPolling() },
            // Files and Apple Intelligence may have changed while another app was in front.
            onBecomeKey: { [weak self] in
                self?.reloadEditors()
                self?.refresh()
            },
            content: { SettingsView(model: self, updater: updater) })
        windows.setTitle(settingsPane.title, id: Self.settingsWindow)
        updateSetupPolling()
    }

    /// Sidebar choice: the window title follows the pane, and the setup pane polls.
    func selectSettingsPane(_ pane: SettingsPane) {
        guard pane != settingsPane else { return }
        settingsPane = pane
        windows.setTitle(pane.title, id: Self.settingsWindow)
        if pane == .setup { refresh() }
        updateSetupPolling()
    }

    /// Closes the settings window if it is open; its panes save pending edits synchronously while it closes.
    func closeSettings() {
        windows.close(id: Self.settingsWindow)
    }

    private static let settingsWindow = "settings"

    /// Polls exactly while the settings window is open on the setup pane.
    private func updateSetupPolling() {
        if windows.isOpen(id: Self.settingsWindow), settingsPane == .setup {
            startSetupPolling()
        } else {
            stopSetupPolling()
        }
    }

    /// Permissions change in System Settings without a notification, so the open setup pane checks every
    /// second. Otherwise nothing polls (idle CPU stays at zero).
    private func startSetupPolling() {
        guard setupPolling == nil else { return }
        setupPolling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                self?.refresh()
            }
        }
    }

    private func stopSetupPolling() {
        setupPolling?.cancel()
        setupPolling = nil
    }

    func showAbout() {
        windows.show(id: "about", title: "Über Zack") { AboutView() }
    }

    // MARK: Setup

    func requestMicrophone() {
        Task {
            _ = await Permissions.requestMicrophone()
            refresh()
        }
    }

    func openSettings(_ pane: Permissions.Pane) {
        if pane == .accessibility { Permissions.promptAccessibility() }
        if pane == .inputMonitoring { Permissions.requestInputMonitoring() }
        NSWorkspace.shared.open(Permissions.settingsURL(pane))
    }

    func adoptModel() {
        do {
            try modelSetup?.adopt()
            setupError = nil
        } catch {
            logger.error("model adopt: \(String(describing: type(of: error)), privacy: .public)")
            setupError = "Übernehmen fehlgeschlagen. Bitte erneut versuchen oder das Modell laden."
        }
        refresh()
    }

    /// Setup "Erneut versuchen" after a failed load: one more attempt.
    func retryModelLoad() {
        modelLoadFailed = false
        refresh()
    }

    /// The only network access of the app: an explicit click in the setup window.
    func downloadModel() {
        guard let modelSetup, downloadProgress == nil else { return }
        downloadProgress = 0
        setupError = nil
        Task {
            do {
                try await modelSetup.download { fraction in
                    Task { @MainActor in
                        if self.downloadProgress != nil { self.downloadProgress = fraction }
                    }
                }
            } catch {
                logger.error("model download: \(String(describing: type(of: error)), privacy: .public)")
                setupError = "Laden fehlgeschlagen. Bitte Netzwerk prüfen und erneut versuchen."
            }
            downloadProgress = nil
            refresh()
        }
    }

    // MARK: Wiring

    private func makeInserter(timing: InsertTiming) -> Inserter {
        Inserter(
            clipboard: SystemClipboard(), keystrokes: CGEventKeystrokes(),
            canPostKeystrokes: { Permissions.accessibility() },
            frontmostBundleID: { CGEventKeystrokes.frontmostBundleID() }, timing: timing)
    }

    /// Hotkey actions run one after the other, so a quick tap cannot overtake its own key down.
    private func startHotkey() {
        let (stream, continuation) = AsyncStream.makeStream(of: (HotkeyAction, FrontApp?).self)
        actions = continuation
        let controller = controller!
        Task {
            for await (action, app) in stream {
                switch action {
                case .begin: await controller.begin(app: app)
                case .confirm: await controller.confirm()
                case .finish: await controller.finish()
                case .cancel: await controller.cancel()
                }
            }
        }
        hotkeyMonitor = HotkeyMonitor(key: hotkey) { [weak self] action in
            guard let self else { return }
            // Timing starts at the key event, before the hop to the dictation actor.
            if action == .begin { signposts.beginPill() }
            // Only a release that ends a recording measures; the controller drops the mark of one that inserts nothing.
            if action == .finish, dictation.isCapturing { signposts.beginInsert() }
            // Read here, on the main thread, at the key event: the front app may change during the hop.
            var app: FrontApp?
            if action == .begin, let front = NSWorkspace.shared.frontmostApplication {
                app = FrontApp(bundleID: front.bundleIdentifier, pid: front.processIdentifier)
            }
            actions?.yield((action, app))
        }
        let memory = memory
        #if DEBUG
            let inputLogger = logger
        #endif
        hotkeyMonitor?.onInput = { [weak self] input in
            #if DEBUG
                switch input {
                case .key: inputLogger.debug("input key")
                case .click: inputLogger.debug("input click")
                }
            #endif
            memory.forget()
            self?.abortOnUnregisteredEscape(input)
        }
        hotkeyMonitor?.start()
    }

    /// Fallback while Esc is not registered (policy off, or the system refused): Esc read along still aborts, and the
    /// app in front gets it as well.
    private func abortOnUnregisteredEscape(_ input: UserInput) {
        guard input == .key(UInt16(Shortcut.cancel.keyCode)), dictation.isProcessing, !escapeRegistered else { return }
        abortDictation()
    }

    /// Straight to the controller, not through the hotkey stream: that one waits behind the running `finish`.
    private func abortDictation() {
        let controller = controller!
        Task { await controller.abort() }
    }

    /// Registers ⌃⌥V and ⌃⌥O; one another app already holds stays out and shows up in `shortcutTaken`.
    private func startShortcuts() {
        let registry = CarbonShortcuts { [weak self] in self?.shortcutPressed($0) }
        shortcuts = registry
        for shortcut in [Shortcut.insertLast, .ruleText] where !registry.register(shortcut) {
            shortcutTaken.insert(shortcut)
        }
    }

    private func shortcutPressed(_ shortcut: Shortcut) {
        logger.info("shortcut \(String(describing: shortcut), privacy: .public)")
        switch shortcut {
        case .cancel: abortDictation()
        case .insertLast: insertLast()
        case .ruleText: replaceWithRuleText()
        }
    }

    /// Esc belongs to Zack only during "Erkenne …" and "KI glättet …"; in every other state the app in front gets it.
    private func updateEscape(for state: DictationState) {
        guard let shortcuts else { return }
        if state.isProcessing {
            escapeRegistered = GlobalShortcutsPolicy.registersEscape && shortcuts.register(.cancel)
        } else {
            shortcuts.unregister(.cancel)
            escapeRegistered = false
        }
    }

    /// Remembers the last active app other than Zack for the code mode menu entry; a switch ends the cursor memory.
    private func observeActivation() {
        if let front = NSWorkspace.shared.frontmostApplication { noteActive(front) }
        activationObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            // Delivered on the main queue (`queue: .main`).
            MainActor.assumeIsolated {
                guard let self, let app, self.noteActive(app) else { return }
                self.memory.forget()
            }
        }
    }

    /// Returns false for Zack itself and for apps without a bundle ID.
    @discardableResult
    private func noteActive(_ app: NSRunningApplication) -> Bool {
        guard let bundleID = app.bundleIdentifier, bundleID != Bundle.main.bundleIdentifier else { return false }
        lastActive = (app.localizedName ?? bundleID, bundleID)
        return true
    }

    private func updateCodeModeApp() {
        guard let lastActive else {
            codeModeApp = nil
            return
        }
        let match = files?.loadCodeApps().match(lastActive.bundleID) ?? .none
        codeModeApp = CodeModeMenuItem(name: lastActive.name, bundleID: lastActive.bundleID, match: match)
    }

    private func observeDictation() {
        let controller = controller!
        Task { [weak self] in
            for await state in controller.states {
                guard let self else { return }
                dictation = state
                pill?.update(state)
                updateEscape(for: state)
                canRetry = await controller.canRetry
                hasLastText = await controller.lastText != nil
                canReplaceWithRuleText = await controller.canReplaceWithRuleText
            }
        }
    }

    /// Recomputes the capture target; a warm input is told only when the target changed.
    private func inputMayHaveChanged() {
        let target = resolveInputTarget()
        if target != inputTarget {
            inputTarget = target
            capture.inputChanged()
        }
        updateMicrophoneMenu()
    }

    private func resolveInputTarget() -> AudioObjectID? {
        MicrophoneChoice.resolve(settings.microphone, in: AudioDevices.inputDevices())
            .deviceID(default: AudioDevices.defaultInputID())
    }

    private func updateMicrophoneMenu() {
        microphoneMenu = MicrophoneMenu(
            saved: settings.microphone, devices: AudioDevices.inputDevices(), defaultID: AudioDevices.defaultInputID(),
            selectionFailed: input.selectionFailed)
    }

    /// Idempotent, so every refresh may call it: with "Immer" the microphone opens as soon as permission and model
    /// are there (app start, permission granted, model loaded or adopted).
    private func applyReadiness() {
        let controller = controller!
        Task { await controller.applyReadiness() }
    }

    /// Refreshes the menu entries that depend on the last dictation (insert, copy, rule text, retry). After Esc the
    /// last dictation arrives once "Abgebrochen" already shows, and a late password verdict drops the retry audio
    /// after the failure showed, so no state brings either; opening the menu does.
    private func updateLastDictationActions() {
        let controller = controller!
        Task {
            canRetry = await controller.canRetry
            hasLastText = await controller.lastText != nil
            canReplaceWithRuleText = await controller.canReplaceWithRuleText
        }
    }

    /// Loads Parakeet in the background and warms it up; a dictation during loading waits for the same load.
    /// A failure stops here: no retry on refresh, until `retryModelLoad`.
    private func loadModelIfReady() {
        guard modelStatus == .ready, !modelLoaded, !modelLoadFailed, loading == nil else { return }
        let transcriber = transcriber
        loading = Task {
            do {
                try await transcriber.prepare()
                try await transcriber.warmUp()
                modelLoaded = true
            } catch {
                logger.error("model load: \(String(describing: type(of: error)), privacy: .public)")
                modelLoadFailed = true
                modelReady.set(false)
                // Show the error instead of leaving it to a yellow icon.
                showSetup()
            }
            loading = nil
        }
    }

    #if DEBUG
        /// Debug: pastes a fixed text after 3 s (time to focus the target app) with restore delay `delay`.
        func debugInsertTest(delay: Duration) {
            let inserter = makeInserter(timing: InsertTiming(defaultDelay: delay))
            Task {
                try? await Task.sleep(for: .seconds(3))
                _ = await inserter.insert("Zack-Einfügetest")
            }
        }

        /// Debug: reads the focused field after 3 s (time to focus the target app) and shows the result.
        func debugReadContext() {
            Task {
                try? await Task.sleep(for: .seconds(3))
                let diagnostics = await AXFocusSource().diagnose()
                // Close first: `show` reuses an open window without replacing its content.
                windows.close(id: "context-debug")
                windows.show(id: "context-debug", title: "Kontext (Debug)") {
                    ContextDebugView(lines: diagnostics.lines)
                }
            }
        }

        /// Debug: opens the window that checks editing shortcuts (spike S1).
        func debugShowEditingSpike() {
            windows.show(id: "editing-spike", title: "Bearbeiten-Test") { EditingSpikeView() }
        }

        /// Debug: holds Esc as a global shortcut for 10 s and logs whether the system allowed it.
        func debugRegisterEscape() {
            guard let shortcuts else { return }
            let ok = shortcuts.register(.cancel)
            logger.info("register cancel: \(ok ? "ok" : "failed", privacy: .public)")
            guard ok else { return }
            Task {
                try? await Task.sleep(for: .seconds(10))
                shortcuts.unregister(.cancel)
            }
        }

        var clipboardAccess: String {
            switch SystemClipboard().access {
            case .ask: "fragen"
            case .alwaysAllow: "immer erlauben"
            case .alwaysDeny: "immer ablehnen"
            }
        }
    #endif
}
