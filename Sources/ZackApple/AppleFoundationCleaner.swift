import FoundationModels
import Synchronization
import ZackCore

/// Whether Apple's on-device model can be used, for the setup window and the menu.
public enum CleanerAvailability: Equatable, Sendable {
    case available
    /// Apple Intelligence is turned off in System Settings.
    case notEnabled
    case deviceNotEligible
    /// macOS is still downloading the model.
    case notReady
}

/// One readied session, keyed by its instructions. The model cools down within seconds, and only the session
/// that was prewarmed stays warm, so the cleanup at release must take that very session.
final class PrewarmSlot<Session: AnyObject>: Sendable {
    private let stored = Mutex<(key: String, session: Session)?>(nil)

    /// The stored session if the key matches, otherwise a new one that replaces any other.
    func session(for key: String, make: () -> Session) -> Session {
        stored.withLock { stored in
            if let current = stored, current.key == key { return current.session }
            let session = make()
            stored = (key, session)
            return session
        }
    }

    /// Removes the stored session; a mismatched key clears the slot and returns nil.
    func take(for key: String) -> Session? {
        stored.withLock { stored in
            defer { stored = nil }
            guard let current = stored, current.key == key else { return nil }
            return current.session
        }
    }

    func clear() {
        stored.withLock { $0 = nil }
    }
}

/// Cleanup with Apple's on-device language model. Never uses the Private Cloud Compute model.
public struct AppleFoundationCleaner: Cleaner {
    public let id = "apple-fm"
    private let slot = PrewarmSlot<LanguageModelSession>()
    /// Greedy decoding: the same dictation always gets the same cleanup, so bench runs are reproducible.
    /// Output is capped by the rule `CleanerPrompt` sets for every cleaner.
    static func options(forInputTokens count: Int) -> GenerationOptions {
        GenerationOptions(
            samplingMode: .greedy, maximumResponseTokens: CleanerPrompt.maxOutputTokens(forInputTokens: count))
    }

    /// UTF-8 byte count: never below the token count, since every token covers at least one byte.
    static func estimatedTokens(for text: String) -> Int {
        text.utf8.count
    }

    /// Instructions, wrapped dictation and output cap must fit the context window.
    static func fits(instructionTokens: Int, promptTokens: Int, inputTokens: Int, contextSize: Int) -> Bool {
        instructionTokens + promptTokens + CleanerPrompt.maxOutputTokens(forInputTokens: inputTokens) <= contextSize
    }

    /// With the byte estimate an upper bound: a fit here is a fit for the model.
    static func fitsByEstimate(_ text: String, instructions: String, contextSize: Int) -> Bool {
        fits(
            instructionTokens: estimatedTokens(for: instructions),
            promptTokens: estimatedTokens(for: CleanerPrompt.wrap(text)),
            inputTokens: estimatedTokens(for: text), contextSize: contextSize)
    }

    /// Input tokens for the output cap, or nil if the dictation does not fit. Short dictations use the estimate
    /// (no counting call, which costs about 25 ms each). Longer ones are counted exactly with the model from
    /// macOS 26.4 on; before that the estimate decides and they keep the rule-based text.
    static func inputTokens(_ text: String, instructions: String, model: SystemLanguageModel) async throws -> Int? {
        if fitsByEstimate(text, instructions: instructions, contextSize: model.contextSize) {
            return estimatedTokens(for: text)
        }
        guard #available(macOS 26.4, *) else { return nil }
        let instructionTokens = try await model.tokenCount(for: Instructions(instructions))
        let promptTokens = try await model.tokenCount(for: CleanerPrompt.wrap(text))
        // The wrapped prompt also stands in for the dictation: slightly more than its tokens, never less.
        let fit = fits(
            instructionTokens: instructionTokens, promptTokens: promptTokens, inputTokens: promptTokens,
            contextSize: model.contextSize)
        return fit ? promptTokens : nil
    }

    public static var availability: CleanerAvailability {
        switch SystemLanguageModel.default.availability {
        case .available: .available
        case .unavailable(.appleIntelligenceNotEnabled): .notEnabled
        case .unavailable(.deviceNotEligible): .deviceNotEligible
        case .unavailable: .notReady
        }
    }

    public init() {}

    public func prepare() async throws {
        try Self.requireAvailable(id: id)
    }

    /// Readies one session for the cleanup that may follow; repeated calls keep that session warm.
    public func prewarm(mode: TextMode, vocabulary: [String]) {
        guard Self.availability == .available else { return }
        let instructions = CleanerPrompt.instructions(mode: mode, vocabulary: vocabulary)
        slot.session(for: instructions) {
            LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        }.prewarm()
    }

    public func discardPrewarmed() {
        slot.clear()
    }

    public func clean(_ text: String, mode: TextMode, vocabulary: [String]) async throws -> String {
        try Self.requireAvailable(id: id)
        let model = SystemLanguageModel.default
        let instructions = CleanerPrompt.instructions(mode: mode, vocabulary: vocabulary)
        guard let inputTokens = try await Self.inputTokens(text, instructions: instructions, model: model) else {
            throw ZackError.inputTooLong
        }
        // One session per dictation, never reused: no context leaks between dictations. A prewarmed session has no
        // transcript and is used once. Dictation is untrusted, so it goes in the prompt (delimited), never into
        // the instructions.
        let session = slot.take(for: instructions) ?? LanguageModelSession(model: model, instructions: instructions)
        let response = try await session.respond(
            to: CleanerPrompt.wrap(text), options: Self.options(forInputTokens: inputTokens))
        return CleanerPrompt.unescape(response.content).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func requireAvailable(id: String) throws {
        let availability = SystemLanguageModel.default.availability
        guard case .available = availability else {
            throw ZackError.engineUnavailable("\(id): \(availability)")
        }
    }
}
