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
}

/// Rule chain, optional language-model cleanup and cursor adaptation.
public struct TextProcessor: Sendable {
    public let vocabulary: Vocabulary
    public let cleaner: (any Cleaner)?
    public let cleanerTimeout: Duration
    private let snippetRule: SnippetRule
    private let rules: [any TextRule]
    private let cursorRule: CursorJoinRule

    public init(
        vocabulary: Vocabulary = Vocabulary(), snippets: [Snippet] = [], cleaner: (any Cleaner)? = nil,
        cleanerTimeout: Duration = .seconds(2)
    ) {
        self.vocabulary = vocabulary
        cursorRule = CursorJoinRule(keeping: vocabulary.terms)
        self.cleaner = cleaner
        self.cleanerTimeout = cleanerTimeout
        snippetRule = SnippetRule(snippets)
        rules = [VocabularyRule(vocabulary), FillerRule(), CodeModeRule()]
    }

    public func process(_ raw: String, context: RuleContext) async -> ProcessingResult {
        if let snippet = snippetRule.match(raw, language: context.language) {
            let final = cursorRule.apply(snippet, context: context)
            return ProcessingResult(
                raw: raw, ruled: snippet, final: final, ruledFinal: final, body: snippet, usedCleaner: false,
                cleanerRejected: false,
                cleanerDuration: nil)
        }
        let ruled = applyRules(raw, context: context)
        guard let cleaner, SignalWords.contains(ruled, language: context.language) else {
            let final = cursorRule.apply(ruled, context: context)
            return ProcessingResult(
                raw: raw, ruled: ruled, final: final, ruledFinal: final, body: ruled,
                usedCleaner: false, cleanerRejected: false, cleanerDuration: nil)
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
        let body = accepted ?? ruled
        return ProcessingResult(
            raw: raw, ruled: ruled, final: cursorRule.apply(body, context: context),
            ruledFinal: cursorRule.apply(ruled, context: context), body: body,
            usedCleaner: accepted != nil, cleanerRejected: accepted == nil, cleanerDuration: duration)
    }

    /// True if `process` would call the cleaner: no snippet, a cleaner is set and a signal word survives the rules.
    public func needsCleaner(_ raw: String, context: RuleContext) -> Bool {
        guard cleaner != nil, snippetRule.match(raw, language: context.language) == nil else { return false }
        return SignalWords.contains(applyRules(raw, context: context), language: context.language)
    }

    private func applyRules(_ raw: String, context: RuleContext) -> String {
        rules.reduce(raw) { $1.apply($0, context: context) }
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
