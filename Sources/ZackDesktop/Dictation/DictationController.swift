import Foundation
import Synchronization
import ZackCore
import os

public enum DictationFailure: Equatable, Sendable {
    case nothingHeard
    case modelMissing
    case microphoneDenied
    case microphoneUnavailable
    case microphoneDisconnected
    case recognitionFailed
    /// The field at key down is a password field: nothing is recognized.
    case passwordField
}

/// A dictation that ended without inserting, though nothing failed; shown like a failure.
public enum DictationNotice: Equatable, Sendable {
    /// The field turned out to be a password field at release; the text stays for "Letztes Diktat kopieren".
    case passwordFieldNotInserted
    /// Esc during recognition or cleanup; the text stays as the last dictation.
    case cancelled
    /// ⌃⌥V before any dictation.
    case noLastDictation
    /// ⌃⌥O without an AI-cleaned dictation to replace.
    case noCleanedVersion
}

public enum DictationState: Equatable, Sendable {
    case idle
    /// Key down, microphone on, pill still hidden (hold threshold).
    case listening
    case recording(elapsed: Duration, level: Float)
    case recognizing
    case cleaning
    case inserted(InsertOutcome)
    /// ⌃⌥O put the rule text in place of the AI-cleaned version, or on the clipboard.
    case ruleText(InsertOutcome)
    case failed(DictationFailure)
    case notice(DictationNotice)

    public var isCapturing: Bool {
        switch self {
        case .listening, .recording: true
        default: false
        }
    }

    /// Recognition or cleanup of a dictation or retry runs; Esc stops it.
    public var isProcessing: Bool {
        switch self {
        case .recognizing, .cleaning: true
        default: false
        }
    }

    var acceptsNewDictation: Bool {
        switch self {
        case .idle, .inserted, .ruleText, .failed, .notice: true
        default: false
        }
    }
}

public enum DictationLimits {
    /// The pill counts down from here.
    public static let hint: Duration = .seconds(165)
    /// Recording ends as if the key was released.
    public static let maximum: Duration = .seconds(180)
    static let tick: Duration = .milliseconds(100)
    static let insertedVisible: Duration = .milliseconds(1_200)
    /// ⌃⌥O replaces the cleaned text in place only this long after the insert; later it goes to the clipboard.
    static let ruleTextWindow: Duration = .seconds(10)
    static let failureVisible: Duration = .seconds(3)
    /// The model cools down after 3 to 6 s without a call (probe 2026-10-29).
    static let prewarmInterval: Duration = .seconds(3)
    /// Longest wait for each focus read at release: the key-down snapshot, the recheck and a read after a change.
    static let recheckGrace: Duration = .milliseconds(100)
}

/// One dictation from key down to inserted text. Audio and text stay in memory; logs carry no content.
public actor DictationController<C: Clock<Duration>> {
    public nonisolated let states: AsyncStream<DictationState>
    private let continuation: AsyncStream<DictationState>.Continuation
    private let capture: MicrophoneCapture
    private let transcriber: any Transcriber
    private let inserter: Inserter
    private let clock: C
    /// Rules, vocabulary and cleaner from the current files and settings.
    private let makeProcessor: @Sendable () async -> TextProcessor
    private let modelReady: @Sendable () -> Bool
    private let microphoneAllowed: @Sendable () -> Bool
    private let signposts: Signposts?
    /// "Mikrofon bereithalten", read at each use so a change applies at once.
    private let readiness: @Sendable () -> MicrophoneReadiness
    /// Reads the focused field; without it there is no text before the cursor from Accessibility.
    private let focus: (any FocusSource)?
    /// Tail of the last insert, for apps that give no text before the cursor.
    private let memory: CursorMemory
    /// Mode for the bundle ID of the app in front, asked at key down.
    private let codeMode: @Sendable (String?) -> TextMode
    /// Dictation language, read once per dictation or repeat so a change applies from the next one.
    private let language: @Sendable () -> DictationLanguage
    private let logger = Logger(subsystem: "com.netclusive.zack", category: "dictation")

    public private(set) var state = DictationState.idle
    /// Final text of the last dictation, for "Letztes Diktat kopieren".
    public private(set) var lastText: String?
    /// Language of the dictation that gave `lastText`, so a repeat joins it under the same rules.
    private var lastLanguage = DictationLanguage.german
    /// The dictation or retry whose recognition gave `lastText`; a password field found by its key-down read later
    /// still drops the text. For a retry that is enough: it only runs once its recording's read is known.
    private var lastTextSession: Int?
    /// Audio of a failed recognition, kept for "Erneut versuchen" until the next dictation; taps and short holds
    /// keep it.
    private struct KeptClip {
        let clip: AudioClip
        /// The dictation that recorded it; its key-down read decides, also after taps or retries since.
        let origin: Int
        /// That read came back without a password field. Until then the audio is not offered.
        var cleared: Bool
        /// The latest retry of it; a password field at its key-down read drops the audio as well.
        var retry: Int?
    }
    private var kept: KeptClip?
    /// Known at key down, shown once the pill would appear, so a quick tap shows nothing.
    private var pendingFailure: DictationFailure?
    private var confirmed = false
    /// Counts dictations; timers of an older one do nothing.
    private var session = 0
    /// Session whose background microphone start failed; set on the capture's queue.
    private nonisolated let failedStart = Mutex(0)
    private var startedAt: C.Instant?
    private var ticker: Task<Void, Never>?
    private var reset: Task<Void, Never>?
    /// Closes a warm microphone once the window after the last dictation is over.
    private var releaseTimer: Task<Void, Never>?
    /// Counts scheduled releases; a timer that woke up late does nothing.
    private var releaseToken = 0
    /// Keeps the model warm while recording; ends with the capture.
    private var prewarmer: Task<Void, Never>?
    /// The cleaner being prewarmed, kept to discard its session if no cleanup takes it.
    private var prewarmedCleaner: (any Cleaner)?
    /// App in front and mode of the running dictation, fixed at key down.
    private var app: FrontApp?
    private var mode = TextMode.prose
    /// Language of the running dictation or retry, fixed with `mode`.
    private var dictationLanguage = DictationLanguage.german
    /// Focus read at key down (or at "Erneut versuchen"); every dictation replaces it, so none sees an earlier one's.
    /// It holds text before the cursor, so it goes once taken or once the dictation ends. Internal for tests.
    private(set) var focusRead: Task<FocusSnapshot, Never>?
    /// The focus read of the running dictation or retry found a password field, also when it came back after the
    /// release grace. Internal for tests.
    private(set) var keyDownIsSecure = false
    /// The focus read of the running dictation or retry came back, whatever it found. Internal for tests.
    private(set) var keyDownSettled = false
    /// Rules and cleanup of the running recognition; Esc cancels it, so the cleaner gives up and the rule text stays.
    private var processing: Task<ProcessingResult, Never>?
    /// Session of the last recognition Esc stopped: it still ends, but only sets the last dictation. Earlier stopped
    /// ones are known by a newer session (`isAborted`).
    private var abortedSession: Int?
    /// The text of the running recognition is on its way into the field; Esc can no longer stop it.
    private var inserting = false
    /// An `insertLast` or `replaceWithRuleText` is reading the focus or pasting; a second call is dropped.
    private var reinserting = false

    /// The last insert of an AI-cleaned dictation, kept for ⌃⌥O until the next dictation (once its pill shows), ⌃⌥V,
    /// retry or insert.
    private struct RuleTextEntry {
        let app: FrontApp?
        let element: FocusElement?
        /// Where the inserted text starts, if the field reported a selection.
        let start: Int?
        let inserted: String
        let ruleText: String
        /// The rule text before it joins the cursor.
        let ruleBody: String
        let at: C.Instant
        /// The dictation or retry it came from, as `lastTextSession`.
        let session: Int
        let language: DictationLanguage
    }
    private var ruleTextEntry: RuleTextEntry?

    public init(
        capture: MicrophoneCapture, transcriber: any Transcriber, inserter: Inserter, clock: C,
        makeProcessor: @escaping @Sendable () async -> TextProcessor, modelReady: @escaping @Sendable () -> Bool,
        microphoneAllowed: @escaping @Sendable () -> Bool, signposts: Signposts? = nil,
        readiness: @escaping @Sendable () -> MicrophoneReadiness = { .off }, focus: (any FocusSource)? = nil,
        memory: CursorMemory = CursorMemory(), codeMode: @escaping @Sendable (String?) -> TextMode = { _ in .prose },
        language: @escaping @Sendable () -> DictationLanguage = { .german }
    ) {
        (states, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(32))
        self.capture = capture
        self.transcriber = transcriber
        self.inserter = inserter
        self.clock = clock
        self.makeProcessor = makeProcessor
        self.modelReady = modelReady
        self.microphoneAllowed = microphoneAllowed
        self.signposts = signposts
        self.readiness = readiness
        self.focus = focus
        self.memory = memory
        self.codeMode = codeMode
        self.language = language
    }

    public var canRetry: Bool { kept?.cleared == true }

    /// ⌃⌥O has an AI-cleaned dictation to work on and no dictation runs.
    public var canReplaceWithRuleText: Bool { ruleTextEntry != nil && state.acceptsNewDictation }

    /// Key down: the microphone starts at once and the focus is read in the background. `app` is the app in front.
    public func begin(app: FrontApp? = nil) {
        guard state.acceptsNewDictation else { return }
        reset?.cancel()
        session += 1
        confirmed = false
        pendingFailure = nil
        startedAt = clock.now
        self.app = app
        mode = codeMode(app?.bundleID)
        dictationLanguage = language()
        focusRead = nil
        keyDownIsSecure = false
        keyDownSettled = false
        publish(.listening)
        if !modelReady() {
            pendingFailure = .modelMissing
        } else if !microphoneAllowed() {
            pendingFailure = .microphoneDenied
        } else {
            // A cold start blocks while the audio engine starts; the actor must not wait for it, or the pill and
            // the release would be late. `stop` and `cancel` queue behind the start.
            let current = session
            capture.startInBackground(
                signposts: signposts,
                onInterruption: { [weak self] in
                    Task { await self?.interrupted(session: current) }
                },
                onFailure: { [weak self] error in
                    self?.failedStart.withLock { $0 = current }
                    let type = String(describing: Swift.type(of: error))
                    Task { await self?.startFailed(session: current, errorType: type) }
                })
        }
        // The pill does not wait for it; the release takes it if it came in time.
        if pendingFailure == nil { readFocus() }
        startTicker()
    }

    /// Held long enough: the pill appears.
    public func confirm() {
        guard state == .listening else { return }
        confirmed = true
        // A new dictation ends what ⌃⌥O could put back; a tap of the key is none.
        ruleTextEntry = nil
        if let pendingFailure {
            stopTicker()
            fail(pendingFailure)
            return
        }
        publish(.recording(elapsed: elapsed(), level: capture.level))
        startPrewarming()
    }

    /// Tap or key combination: audio is dropped, nothing appears.
    public func cancel() {
        guard state.isCapturing else { return }
        stopTicker()
        focusRead = nil
        // Published first: `capture.cancel` waits for a start that is still running.
        publish(.idle)
        discardPrewarmed()
        if pendingFailure == nil { capture.cancel() }
    }

    /// Key released.
    public func finish() async {
        await end(measured: true)
    }

    /// Esc during recognition or cleanup: nothing is inserted. The recognition runs to its end, a cleanup stops at
    /// once; the result becomes the last dictation. Runs while `finish` still waits for that recognition.
    public func abort() {
        guard state.isProcessing, !inserting else { return }
        let phase = state == .cleaning ? "cleaning" : "recognizing"
        abortedSession = session
        processing?.cancel()
        discardPrewarmed()
        signposts?.discardInsert()
        logger.info("aborted while \(phase, privacy: .public)")
        publish(.notice(.cancelled))
        scheduleReset(after: DictationLimits.failureVisible)
    }

    /// Ends the recording. `measured` if a key release began the insert mark (`Signposts`), not the time limit.
    private func end(measured: Bool) async {
        guard state.isCapturing else {
            // A release that ends nothing drops its mark; a running recognition ends its own.
            if !state.isProcessing { signposts?.discardInsert() }
            return
        }
        stopTicker()
        if let pendingFailure {
            fail(pendingFailure)
            return
        }
        // Held shorter than any dictation: ends silently like a tap. Measured on the
        // clock up to the release, not on the clip, which may start with the pre-roll of a ready microphone.
        guard elapsed() >= .seconds(EngineLimits.minimumClipDuration) else {
            focusRead = nil
            signposts?.discardInsert()
            discardPrewarmed()
            publish(.idle)
            capture.cancel()
            return
        }
        // Waits for the rest of a start in the background; a failure is known from then on, before its hop to
        // the actor arrives.
        capture.waitForControl()
        if failedStart.withLock({ $0 }) == session {
            fail(.microphoneUnavailable)
            return
        }
        // A dictation replaces the audio kept for "Erneut versuchen" and ends the ⌃⌥O entry, also when a release
        // after the threshold came before the pill's tick, so `confirm` never ran.
        kept = nil
        ruleTextEntry = nil
        // Keep the running input open if the setting asks for it; `stop` then leaves it running.
        if readiness() != .off {
            do {
                try capture.warmUp(preRoll: MicrophoneReadiness.preRoll)
            } catch {
                logger.error("microphone warm-up failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
        let clip = capture.stop()
        // The window counts from key release, so it cannot end unnoticed during recognition.
        keepReadyAfterDictation()
        guard clip.duration >= EngineLimits.minimumClipDuration, !EngineLimits.isSilent(clip) else {
            fail(.nothingHeard)
            return
        }
        await recognize(clip, measured: measured)
    }

    /// Menu "Erneut versuchen" after a failed recognition, once the recording's key-down read found no password field.
    public func retry() async {
        guard let clip = kept?.clip, kept?.cleared == true, state.acceptsNewDictation else { return }
        // No key down or release: open marks belong to an earlier tap or release and would measure the retry.
        signposts?.discardPill()
        signposts?.discardInsert()
        reset?.cancel()
        session += 1
        kept?.retry = session
        // No key down tells the app in front: prose, a fresh focus read and no memory.
        app = nil
        mode = .prose
        dictationLanguage = language()
        keyDownIsSecure = false
        keyDownSettled = false
        ruleTextEntry = nil
        readFocus()
        await recognize(clip, measured: false, retrying: true)
    }

    /// ⌃⌥V: the last dictation again, at the cursor of the app in front. Only while no dictation runs; it starts no
    /// session of its own and leaves a dictation's Esc marks alone.
    public func insertLast(app: FrontApp?) async {
        // A second ⌃⌥V during the read or the paste would insert twice.
        guard !reinserting, state.acceptsNewDictation else { return }
        reinserting = true
        defer { reinserting = false }
        let started = session
        ruleTextEntry = nil
        guard let text = lastText else {
            publish(.notice(.noLastDictation))
            scheduleReset(after: DictationLimits.failureVisible)
            return
        }
        let read = focus.map { focus in Task { await focus.read(text: true) } }
        let snapshot = await withinGrace(read) ?? .unknown
        // A key down during the read: that dictation owns the pill now.
        guard state.acceptsNewDictation else { return }
        if snapshot.isSecure {
            logger.info("not inserted: password field")
            publish(.notice(.passwordFieldNotInserted))
            scheduleReset(after: DictationLimits.failureVisible)
            return
        }
        let resolved = ContextResolver.resolve(snapshot, memory: memory.text(app: app, element: snapshot.element))
        let context = RuleContext(
            mode: codeMode(app?.bundleID), textBeforeCursor: resolved.text, language: lastLanguage)
        let outcome = await inserter.insert(CursorJoinRule().apply(text, context: context))
        // The text landed, so the memory knows it, whatever the pill shows.
        if outcome == .pasted { memory.remember(text, app: app, element: snapshot.element) }
        logger.info("inserted last: context \(resolved.source.rawValue, privacy: .public)")
        // A dictation that started meanwhile owns the pill and its reset.
        guard session == started, state.acceptsNewDictation else { return }
        publish(.inserted(outcome))
        scheduleReset(after: DictationLimits.insertedVisible)
    }

    /// ⌃⌥O: the rule text instead of the AI-cleaned one just inserted. Within `ruleTextWindow` and while the field
    /// still holds exactly that text, it is selected and replaced; otherwise the rule text goes to the clipboard.
    public func replaceWithRuleText() async {
        // Shares the guard with `insertLast`: the two must not overlap.
        guard !reinserting, state.acceptsNewDictation else { return }
        reinserting = true
        defer { reinserting = false }
        let started = session
        guard let entry = ruleTextEntry else {
            publish(.notice(.noCleanedVersion))
            scheduleReset(after: DictationLimits.failureVisible)
            return
        }
        ruleTextEntry = nil
        let outcome: InsertOutcome
        if let selected = await selectInsertedText(entry, session: started) {
            // A key down during the focus calls: that dictation owns the pill now. Its paste must not replace the
            // text just selected, so the selection collapses behind it.
            guard session == started, state.acceptsNewDictation else {
                // Guarded like `AXFocusSource.placeCaret`: the start comes from the app.
                if let focus, let element = entry.element, selected.length <= Int.max - selected.location {
                    _ = await focus.select(
                        TextRange(location: selected.location + selected.length, length: 0), in: element)
                }
                return
            }
            outcome = await inserter.insert(entry.ruleText)
            if outcome == .pasted { memory.remember(entry.ruleText, app: entry.app, element: entry.element) }
        } else {
            guard session == started, state.acceptsNewDictation else { return }
            await inserter.copy(entry.ruleBody)
            outcome = .clipboardOnly
        }
        lastText = entry.ruleBody
        lastLanguage = entry.language
        lastTextSession = entry.session
        logger.info("rule text: pasted \(outcome == .pasted, privacy: .public)")
        guard session == started, state.acceptsNewDictation else { return }
        publish(.ruleText(outcome))
        scheduleReset(after: DictationLimits.insertedVisible)
    }

    /// Selects the inserted text if it is still in place: in time, same field, same text at the same place. Returns
    /// the selected range, nil if nothing was selected.
    private func selectInsertedText(_ entry: RuleTextEntry, session started: Int) async -> TextRange? {
        guard let focus, let element = entry.element, let start = entry.start,
            entry.at.duration(to: clock.now) <= DictationLimits.ruleTextWindow
        else { return nil }
        let read = Task { await focus.read(text: false) }
        guard await withinGrace(read)?.element == element, session == started, state.acceptsNewDictation else {
            return nil
        }
        let range = TextRange(location: start, length: entry.inserted.utf16.count)
        guard await focus.text(in: range, of: element) == entry.inserted, session == started,
            state.acceptsNewDictation
        else { return nil }
        return await focus.select(range, in: element) ? range : nil
    }

    /// Starts the focus read of the running dictation or retry. Besides `recognize` taking it within the grace, it
    /// hops back on its own: a password field ends a recording while the key is held, and a verdict after the grace
    /// still drops the result.
    private func readFocus() {
        guard let focus else {
            focusRead = nil
            return
        }
        let read = Task { await focus.read(text: true) }
        focusRead = read
        let current = session
        Task {
            let snapshot = await read.value
            self.keyDownRead(snapshot, session: current)
        }
    }

    /// `retrying` for "Erneut versuchen": `clip` is the kept audio, not a new recording.
    private func recognize(_ clip: AudioClip, measured: Bool, retrying: Bool = false) async {
        let current = session
        publish(.recognizing)
        let app = app
        let mode = mode
        let language = dictationLanguage
        // The key-down snapshot is normally there long ago. If it does not come in time, the app does not answer:
        // no context and no recheck. Otherwise the recheck runs alongside the recognition. Taken once; the snapshot
        // lives on only in this call.
        let read = focusRead
        focusRead = nil
        let keyDown = await withinGrace(read)
        // A password field at key down that ended no recording (released already, or a retry): no recognition at all.
        if keyDown?.isSecure == true || keyDownIsSecure {
            // As `settleKeptClip` does once the read's own hop arrives; here before the failure shows.
            if retrying, kept?.retry == current { kept = nil }
            fail(.passwordField, recognition: current)
            return
        }
        let recheck = keyDown == nil ? nil : focus.map { focus in Task { await focus.read(text: false) } }
        let processor = await makeProcessor()
        let raw: String
        do {
            raw = try await transcriber.transcribe(clip, hints: processor.vocabulary.terms)
        } catch {
            logger.error("recognition failed: \(String(describing: type(of: error)), privacy: .public)")
            // After Esc the audio kept for "Erneut versuchen" stays as it was; it may belong to a newer retry. A
            // password field drops it, a failed retry keeps it. A failed dictation keeps its audio, offered only
            // once its key-down read is known to have found no password field: in time, back meanwhile, or no focus
            // reader at all, as the insert would treat it.
            if !isAborted(current) {
                if keyDownIsSecure {
                    kept = nil
                } else if !retrying {
                    kept = KeptClip(
                        clip: clip, origin: current, cleared: keyDown != nil || keyDownSettled || focus == nil)
                }
            }
            fail(keyDownIsSecure ? .passwordField : .recognitionFailed, recognition: current)
            return
        }
        if !isAborted(current) { kept = nil }
        // The key-down read came back during the recognition: the text goes nowhere, not even to the cleaner.
        if current == session, keyDownIsSecure {
            fail(.passwordField, recognition: current)
            return
        }
        let snapshot = await settledSnapshot(keyDown: keyDown, recheck: recheck)
        let resolved = ContextResolver.resolve(snapshot, memory: memory.text(app: app, element: snapshot.element))
        let context = RuleContext(mode: mode, textBeforeCursor: resolved.text, language: language)
        let result = await process(raw, context: context, with: processor, recognition: current)
        // Replaced after Esc by a newer dictation or retry: cleaner session, password flag and last dictation are
        // that one's now.
        guard current == session else { return }
        // Nothing takes a session that was left over: no signal word, rejected or timed out.
        processor.cleaner?.discardPrewarmed()
        prewarmedCleaner = nil
        // The key-down read came back during the cleanup: the result goes nowhere, not even into "Letztes Diktat
        // kopieren".
        if keyDownIsSecure {
            fail(.passwordField, recognition: current)
            return
        }
        guard !result.final.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            fail(.nothingHeard, recognition: current)
            return
        }
        lastText = result.body
        lastLanguage = language
        lastTextSession = current
        // Esc: the text stays for "Letztes Diktat kopieren", nothing else happens.
        guard !isAborted(current) else { return }
        // The focus moved to a password field during the dictation: neither the field nor the clipboard gets the
        // text, and the memory stays as it was.
        if snapshot.isSecure {
            signposts?.discardInsert()
            logger.info("not inserted: password field at release")
            publish(.notice(.passwordFieldNotInserted))
            scheduleReset(after: DictationLimits.failureVisible)
            return
        }
        // Set in the same step as the check above: an Esc after it finds the text on its way.
        inserting = true
        let outcome = await inserter.insert(result.final)
        inserting = false
        // Only a paste puts the text before the cursor; text left on the clipboard is not in the field.
        // A password verdict during the paste: the text landed, but none of it is kept.
        if outcome == .pasted, !keyDownIsSecure { memory.remember(result.final, app: app, element: snapshot.element) }
        if measured {
            signposts?.endInsert(usedCleaner: result.usedCleaner, audioSeconds: clip.duration)
        } else {
            signposts?.discardInsert()
        }
        logger.info(
            "inserted: audio \(clip.duration, format: .fixed(precision: 1), privacy: .public) s, cleaner \(result.usedCleaner, privacy: .public), rejected \(result.cleanerRejected, privacy: .public), context \(resolved.source.rawValue, privacy: .public), mode \(mode.rawValue, privacy: .public)"
        )
        // Only an accepted cleaner output differs from the rule text; ⌃⌥O has something to put back then.
        ruleTextEntry =
            result.usedCleaner && !keyDownIsSecure
            ? RuleTextEntry(
                app: app, element: snapshot.element, start: snapshot.selection?.location, inserted: result.final,
                ruleText: result.ruledFinal, ruleBody: result.ruled, at: clock.now, session: current,
                language: language) : nil
        publish(.inserted(outcome))
        scheduleReset(after: DictationLimits.insertedVisible)
    }

    /// Rules and cleanup in a task that `abort` cancels; after an Esc during the recognition it is cancelled at once,
    /// so the cleaner is not waited for and the rule text comes back.
    private func process(
        _ raw: String, context: RuleContext, with processor: TextProcessor, recognition current: Int
    ) async -> ProcessingResult {
        let aborted = isAborted(current)
        if !aborted, processor.needsCleaner(raw, context: context) { publish(.cleaning) }
        let task = Task { await processor.process(raw, context: context) }
        if aborted { task.cancel() } else { processing = task }
        let result = await task.value
        if processing == task { processing = nil }
        return result
    }

    /// The snapshot the text joins to: the key-down one, unless the recheck shows another element or selection.
    /// Then the text is read again; if that read misses the grace, the recheck stands (it carries no text).
    private func settledSnapshot(keyDown: FocusSnapshot?, recheck: Task<FocusSnapshot, Never>?) async -> FocusSnapshot {
        guard let keyDown else { return .unknown }
        guard let focus, let current = await withinGrace(recheck) else { return keyDown }
        // Nothing is read from a password field; the recheck says enough.
        if current.isSecure { return current }
        guard current.element != keyDown.element || current.selection != keyDown.selection else { return keyDown }
        return await withinGrace(Task { await focus.read(text: true) }) ?? current
    }

    /// The snapshot of `read`, or nil once `recheckGrace` has passed on the clock. A read that hangs is left behind:
    /// waiting on `Task.value` would ignore the cancellation, a stream's iterator ends with it.
    private func withinGrace(_ read: Task<FocusSnapshot, Never>?) async -> FocusSnapshot? {
        guard let read else { return nil }
        let (arrival, delivery) = AsyncStream.makeStream(of: FocusSnapshot.self)
        Task {
            delivery.yield(await read.value)
            delivery.finish()
        }
        let clock = clock
        return await withTaskGroup(of: FocusSnapshot?.self) { group in
            group.addTask {
                for await snapshot in arrival { return snapshot }
                return nil
            }
            group.addTask {
                try? await clock.sleep(for: DictationLimits.recheckGrace)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func startTicker() {
        let current = session
        ticker = Task { [clock] in
            while !Task.isCancelled {
                do { try await clock.sleep(for: DictationLimits.tick) } catch { return }
                self.tick(session: current)
            }
        }
    }

    /// Every end of a capture stops the ticker, and with it the prewarming.
    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
        prewarmer?.cancel()
        prewarmer = nil
    }

    /// Readies one cleaner session every `prewarmInterval` until the capture ends; the cleanup at release takes it.
    /// A prewarmed session only serves a cleanup with the same mode, so it uses the mode and language of this dictation.
    private func startPrewarming() {
        let mode = mode
        let language = dictationLanguage
        prewarmer = Task { [clock] in
            let processor = await makeProcessor()
            guard let cleaner = processor.cleaner, !Task.isCancelled else { return }
            prewarmedCleaner = cleaner
            let terms = processor.vocabulary.terms
            while !Task.isCancelled {
                cleaner.prewarm(mode: mode, vocabulary: terms, language: language)
                do { try await clock.sleep(for: DictationLimits.prewarmInterval) } catch { return }
            }
        }
    }

    /// The dictation ends without a cleanup: a readied session would only go stale.
    private func discardPrewarmed() {
        prewarmedCleaner?.discardPrewarmed()
        prewarmedCleaner = nil
    }

    private func tick(session current: Int) {
        guard current == session, state.isCapturing else { return }
        let elapsed = elapsed()
        if elapsed >= DictationLimits.maximum {
            // A new task: `end` cancels the ticker, which must not cancel recognition.
            Task { await self.finishAtLimit(session: current) }
            return
        }
        if confirmed, pendingFailure == nil { publish(.recording(elapsed: elapsed, level: capture.level)) }
    }

    /// The background start failed: shown at once during a recording, otherwise once the pill would appear.
    private func startFailed(session current: Int, errorType: String) {
        logger.error("microphone start failed: \(errorType, privacy: .public)")
        guard current == session, state.isCapturing else { return }
        guard confirmed else {
            pendingFailure = .microphoneUnavailable
            return
        }
        stopTicker()
        fail(.microphoneUnavailable)
    }

    /// The device went away: the audio is dropped. During a recording the hint shows at once; inside the tap window
    /// it waits for `confirm`, so a tap stays silent, and the window of a ready microphone goes on as after a tap.
    private func interrupted(session current: Int) {
        guard current == session, state.isCapturing else { return }
        capture.cancel()
        guard confirmed else {
            pendingFailure = .microphoneDisconnected
            return
        }
        stopTicker()
        fail(.microphoneDisconnected)
        keepReadyAfterDictation()
    }

    /// The key-down snapshot of dictation or retry `current`, back from its read. It first settles the kept audio, also
    /// for an older session. For the running one a password field is noted for `recognize`; during the recording it
    /// drops the audio as a lost device does. An earlier failure stands.
    private func keyDownRead(_ snapshot: FocusSnapshot, session current: Int) {
        settleKeptClip(snapshot, session: current)
        if snapshot.isSecure { dropResult(of: current) }
        guard current == session else { return }
        keyDownSettled = true
        guard snapshot.isSecure else { return }
        keyDownIsSecure = true
        guard state.isCapturing, pendingFailure == nil else { return }
        logger.info("password field at key down")
        // A cold start may still run on the capture's queue; the pill must not wait for it. The drop queues behind
        // that start and before any later call from here, such as the next dictation's start.
        capture.cancelInBackground()
        guard confirmed else {
            pendingFailure = .passwordField
            return
        }
        stopTicker()
        // Published first: in `off` mode the release below waits for the start as well.
        fail(.passwordField)
        keepReadyAfterDictation()
    }

    /// The kept audio and the key-down read of session `current`, matched by session even after taps or retries
    /// since: the read of the recording drops the audio on a password field and offers it otherwise; a password field
    /// at a retry of it drops it too.
    private func settleKeptClip(_ snapshot: FocusSnapshot, session current: Int) {
        guard let held = kept else { return }
        if held.origin == current {
            if snapshot.isSecure { kept = nil } else { kept?.cleared = true }
        } else if held.retry == current, snapshot.isSecure {
            kept = nil
        }
    }

    /// A password field found by the key-down read of `current` after its text was kept, also after taps or dictations
    /// since: the last dictation, the ⌃⌥O entry and the cursor memory let go of it. Text already inserted stays where
    /// it landed.
    private func dropResult(of current: Int) {
        if lastTextSession == current {
            lastText = nil
            lastLanguage = .german
            lastTextSession = nil
            memory.forget()
        }
        if ruleTextEntry?.session == current { ruleTextEntry = nil }
    }

    /// The time limit of dictation `current`, as if the key was released. A task that runs late, after that
    /// dictation ended and the next one began, does nothing.
    func finishAtLimit(session current: Int) async {
        guard current == session else { return }
        await end(measured: false)
    }

    /// App start and setting changes: `off` closes the input now (or when the running dictation ends),
    /// `afterDictation` starts the window now if the input is still warm, `always` opens the input once model and
    /// microphone permission are there.
    public func applyReadiness() {
        let readiness = readiness()
        switch readiness {
        case .off:
            cancelRelease()
            // A cold input is closed already or closes when its recording ends. `release` would also wait for a
            // start still running in the background, and the pill with it.
            if capture.isWarm { capture.release() }
        case .afterDictation:
            if capture.isWarm, releaseTimer == nil, !state.isCapturing, let window = readiness.window {
                scheduleRelease(after: window)
            }
        case .always:
            cancelRelease()
            guard !capture.isWarm, modelReady(), microphoneAllowed() else { return }
            do {
                try capture.warmUp(preRoll: MicrophoneReadiness.preRoll)
            } catch {
                logger.error("microphone warm-up failed: \(String(describing: type(of: error)), privacy: .public)")
            }
        }
    }

    /// After a dictation (taps and holds under 0.3 s do not count): close the input, keep it for the window
    /// (which starts again), or keep it open.
    private func keepReadyAfterDictation() {
        let readiness = readiness()
        cancelRelease()
        switch readiness {
        case .off: capture.release()
        case .afterDictation: if let window = readiness.window { scheduleRelease(after: window) }
        case .always: break
        }
    }

    private func scheduleRelease(after window: Duration) {
        releaseToken += 1
        let token = releaseToken
        releaseTimer = Task { [clock] in
            do { try await clock.sleep(for: window) } catch { return }
            self.windowEnded(token: token)
        }
    }

    private func cancelRelease() {
        releaseToken += 1
        releaseTimer?.cancel()
        releaseTimer = nil
    }

    /// During a recording the input closes when it ends; a finished dictation keeps it warm and starts the window
    /// again, a cancelled tap or a short hold does not.
    private func windowEnded(token: Int) {
        guard token == releaseToken else { return }
        releaseTimer = nil
        capture.release()
    }

    private func elapsed() -> Duration {
        startedAt.map { $0.duration(to: clock.now) } ?? .zero
    }

    /// Esc stopped recognition `current`. Also true once a newer dictation or retry began: one can only start after
    /// this recognition left "Erkenne …" and "KI glättet …", and before its end only `abort` does that. A second Esc
    /// for the newer one overwrites `abortedSession`, so the session check carries the first.
    private func isAborted(_ current: Int) -> Bool {
        abortedSession == current || current != session
    }

    /// A failure of recognition `current`. After Esc the pill keeps showing "Abgebrochen".
    private func fail(_ failure: DictationFailure, recognition current: Int) {
        guard !isAborted(current) else { return }
        fail(failure)
    }

    private func fail(_ failure: DictationFailure) {
        // The dictation or retry ends here; a key-down snapshot not taken yet goes with it.
        focusRead = nil
        // Nothing is inserted, so an open insert mark measures nothing; it cannot belong to another recognition,
        // since a failure ends the only dictation or retry that runs.
        signposts?.discardInsert()
        discardPrewarmed()
        publish(.failed(failure))
        scheduleReset(after: DictationLimits.failureVisible)
    }

    private func scheduleReset(after delay: Duration) {
        let current = session
        reset?.cancel()
        reset = Task { [clock] in
            do { try await clock.sleep(for: delay) } catch { return }
            self.hideResult(session: current)
        }
    }

    private func hideResult(session current: Int) {
        guard current == session, !state.isCapturing, state != .idle else { return }
        publish(.idle)
    }

    private func publish(_ newState: DictationState) {
        state = newState
        continuation.yield(newState)
    }
}
