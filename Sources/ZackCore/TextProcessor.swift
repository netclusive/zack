import Synchronization

public struct ProcessingResult: Sendable, Equatable {
    public let raw: String
    public let ruled: String
    public let final: String
    /// The rule text with the same cursor join as `final`; equal to `final` without an accepted cleaner output.
    public let ruledFinal: String
    /// The text before it joins the cursor: snippet, accepted cleaner output or rule text.
    public let body: String
    public let usedCleaner: Bool
    /// Cleaner ran but its output was not used (timeout, error or implausible).
    public let cleanerRejected: Bool
    public let cleanerDuration: Duration?
    /// The second opinion was called.
    public let checked: Bool
    /// The second opinion replaced at least one marked range; `body` is the spliced text.
    public let usedCheck: Bool
    public let checkDuration: Duration?
    /// Words below `TermCheck.threshold`; 0 where the term check does not apply.
    public let markedWords: Int

    init(
        raw: String, ruled: String, final: String, ruledFinal: String, body: String, usedCleaner: Bool = false,
        cleanerRejected: Bool = false, cleanerDuration: Duration? = nil, checked: Bool = false,
        usedCheck: Bool = false, checkDuration: Duration? = nil, markedWords: Int = 0
    ) {
        self.raw = raw
        self.ruled = ruled
        self.final = final
        self.ruledFinal = ruledFinal
        self.body = body
        self.usedCleaner = usedCleaner
        self.cleanerRejected = cleanerRejected
        self.cleanerDuration = cleanerDuration
        self.checked = checked
        self.usedCheck = usedCheck
        self.checkDuration = checkDuration
        self.markedWords = markedWords
    }
}

/// Rule chain, optional language-model cleanup, optional term check and cursor adaptation.
public struct TextProcessor: Sendable {
    public let vocabulary: Vocabulary
    public let cleaner: (any Cleaner)?
    public let cleanerTimeout: Duration
    public let secondOpinion: (any SecondOpinion)?
    public let checkTimeout: Duration
    private let snippetRule: SnippetRule
    private let rules: [any TextRule]
    /// Number formats; also applied to an accepted cleaner output, which does not run through `rules`.
    private static let formatting: [any TextRule] = [TimeRule(), NumberRule(), UnitRule()]
    private let cursorRule: CursorJoinRule

    public init(
        vocabulary: Vocabulary = Vocabulary(), snippets: [Snippet] = [], cleaner: (any Cleaner)? = nil,
        cleanerTimeout: Duration = .seconds(2), secondOpinion: (any SecondOpinion)? = nil,
        checkTimeout: Duration = TermCheck.timeout
    ) {
        self.vocabulary = vocabulary
        cursorRule = CursorJoinRule(keeping: vocabulary.terms)
        self.cleaner = cleaner
        self.cleanerTimeout = cleanerTimeout
        self.secondOpinion = secondOpinion
        self.checkTimeout = checkTimeout
        snippetRule = SnippetRule(snippets)
        rules = [VocabularyRule(vocabulary), FillerRule()] + Self.formatting + [CodeModeRule()]
    }

    public func process(_ raw: String, context: RuleContext) async -> ProcessingResult {
        await process(Recognition(text: raw), audio: nil, context: context)
    }

    /// `audio` and the recognized words feed the term check; without them the result equals `process(_:context:)`.
    public func process(_ recognition: Recognition, audio: AudioClip?, context: RuleContext) async -> ProcessingResult {
        let raw = recognition.text
        if let snippet = snippetRule.match(raw, language: context.language) {
            let final = cursorRule.apply(snippet, context: context)
            return ProcessingResult(raw: raw, ruled: snippet, final: final, ruledFinal: final, body: snippet)
        }
        let ruled = applyingRules(raw, context: context)
        guard let cleaner, SignalWords.contains(ruled, language: context.language, original: raw) else {
            if let secondOpinion, let audio,
                let marked = checkTarget(recognition, ruled: ruled, audio: audio, context: context)
            {
                return await checking(raw: raw, ruled: ruled, marked: marked, by: secondOpinion, audio: audio, context)
            }
            let final = cursorRule.apply(ruled, context: context)
            return ProcessingResult(raw: raw, ruled: ruled, final: final, ruledFinal: final, body: ruled)
        }

        let start = ContinuousClock.now
        let terms = vocabulary.terms
        let language = context.language
        let cleaned = try? await Self.withTimeout(cleanerTimeout) {
            try await cleaner.clean(ruled, mode: context.mode, vocabulary: terms, language: language)
        }
        let duration = ContinuousClock.now - start
        let accepted = cleaned.flatMap { Plausibility.accept(input: ruled, output: $0) ? $0 : nil }
            .map { Self.restoringTerminator(of: ruled, in: $0) }
            .map { output in Self.formatting.reduce(output) { $1.apply($0, context: context) } }
        let body = accepted ?? ruled
        return ProcessingResult(
            raw: raw, ruled: ruled, final: cursorRule.apply(body, context: context),
            ruledFinal: cursorRule.apply(ruled, context: context), body: body,
            usedCleaner: accepted != nil, cleanerRejected: accepted == nil, cleanerDuration: duration)
    }

    /// True if `process` would call the cleaner: no snippet, a cleaner is set and a signal word survives the rules.
    public func needsCleaner(_ raw: String, context: RuleContext) -> Bool {
        guard cleaner != nil, snippetRule.match(raw, language: context.language) == nil else { return false }
        return SignalWords.contains(
            applyingRules(raw, context: context), language: context.language, original: raw)
    }

    /// The rule chain without snippet, cleaner or cursor join.
    public func applyingRules(_ raw: String, context: RuleContext) -> String {
        rules.reduce(raw) { $1.apply($0, context: context) }
    }

    /// True if the term check may look at this dictation: prose, no snippet and no signal word after the rules.
    /// Independent of whether a cleaner or second opinion is set.
    public func checkApplies(_ raw: String, context: RuleContext) -> Bool {
        checkApplies(raw, ruled: applyingRules(raw, context: context), context: context)
    }

    /// True if `process` would call the second opinion.
    public func needsCheck(_ recognition: Recognition, audio: AudioClip?, context: RuleContext) -> Bool {
        guard let audio else { return false }
        let ruled = applyingRules(recognition.text, context: context)
        return checkTarget(recognition, ruled: ruled, audio: audio, context: context) != nil
    }

    private func checkApplies(_ raw: String, ruled: String, context: RuleContext) -> Bool {
        guard context.mode == .prose, snippetRule.match(raw, language: context.language) == nil else { return false }
        return !SignalWords.contains(ruled, language: context.language, original: raw)
    }

    /// The rule text with its unsure words marked, if the term check applies and marks at least one word.
    private func checkTarget(_ recognition: Recognition, ruled: String, audio: AudioClip, context: RuleContext)
        -> MarkedText?
    {
        guard secondOpinion != nil, audio.duration <= TermCheck.maxAudioSeconds, !vocabulary.terms.isEmpty,
            checkApplies(recognition.text, ruled: ruled, context: context)
        else { return nil }
        let segments = SuspiciousWords.annotate(ruled, words: recognition.words, terms: vocabulary.terms)
        let marked = SuspiciousWords.marked(segments, below: TermCheck.threshold)
        return marked.markedCount > 0 ? marked : nil
    }

    /// Asks the second opinion and splices its rule text into the marked ranges; any failure keeps the rule text.
    private func checking(
        raw: String, ruled: String, marked: MarkedText, by secondOpinion: any SecondOpinion, audio: AudioClip,
        _ context: RuleContext
    ) async -> ProcessingResult {
        let start = ContinuousClock.now
        let terms = vocabulary.terms
        let focus = TermSplice.focus(marked)
        let language = context.language
        let other = try? await Self.withTimeout(checkTimeout) {
            try await secondOpinion.recognize(audio, terms: terms, focus: focus, language: language)
        }
        let duration = ContinuousClock.now - start
        let spliced = other.map { TermSplice.apply(marked, other: applyingRules($0, context: context)) }
        let usedCheck = (spliced?.replacedRuns ?? 0) > 0
        let body = usedCheck ? spliced?.text ?? ruled : ruled
        return ProcessingResult(
            raw: raw, ruled: ruled, final: cursorRule.apply(body, context: context),
            ruledFinal: cursorRule.apply(ruled, context: context), body: body, checked: true, usedCheck: usedCheck,
            checkDuration: duration, markedWords: marked.markedCount)
    }

    /// Cleaners tend to drop the final sentence mark; put the one from the rule output back.
    static func restoringTerminator(of ruled: String, in cleaned: String) -> String {
        guard let terminator = ruled.last, ".!?…".contains(terminator),
            let last = cleaned.last, last.isLetter || last.isNumber
        else { return cleaned }
        return cleaned + String(terminator)
    }

    /// Returns the first of result, timeout or caller cancellation, without waiting for a cleaner that ignores
    /// cancellation.
    static func withTimeout<T: Sendable>(
        _ timeout: Duration, operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let gate = ResumeGate<T>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                gate.track(
                    Task {
                        do {
                            gate.resume(with: .success(try await operation()))
                        } catch { gate.resume(with: .failure(error)) }
                    })
                gate.track(
                    Task {
                        try? await Task.sleep(for: timeout)
                        gate.resume(with: .failure(ZackError.timeout))
                    })
            }
        } onCancel: {
            gate.resume(with: .failure(CancellationError()))
        }
    }
}

/// Delivers the first result to a continuation exactly once and cancels all tracked tasks when it does.
/// The result may arrive before the continuation is installed.
final class ResumeGate<T: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<T, any Error>?
        var result: Result<T, any Error>?
        var tasks: [Task<Void, Never>] = []
        var finished = false
    }

    private let state = Mutex(State())

    func install(_ continuation: CheckedContinuation<T, any Error>) {
        let stored = state.withLock { state -> Result<T, any Error>? in
            if let result = state.result { return result }
            state.continuation = continuation
            return nil
        }
        if let stored { continuation.resume(with: stored) }
    }

    /// Registers a task to cancel on completion; cancels it at once if the gate already finished.
    func track(_ task: Task<Void, Never>) {
        let finished = state.withLock { state -> Bool in
            if !state.finished { state.tasks.append(task) }
            return state.finished
        }
        if finished { task.cancel() }
    }

    func resume(with result: Result<T, any Error>) {
        let (pending, tasks) = state.withLock { state -> (CheckedContinuation<T, any Error>?, [Task<Void, Never>]) in
            guard !state.finished else { return (nil, []) }
            state.finished = true
            let pending = state.continuation
            let tasks = state.tasks
            state.continuation = nil
            state.tasks = []
            if pending == nil { state.result = result }
            return (pending, tasks)
        }
        pending?.resume(with: result)
        for task in tasks { task.cancel() }
    }
}
