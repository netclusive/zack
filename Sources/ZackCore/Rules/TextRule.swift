/// Information about where the dictation will be inserted.
public struct RuleContext: Sendable, Equatable {
    public var mode: TextMode
    /// Text left of the cursor in the target field, if the app exposes it.
    public var textBeforeCursor: String?

    public init(mode: TextMode = .prose, textBeforeCursor: String? = nil) {
        self.mode = mode
        self.textBeforeCursor = textBeforeCursor
    }
}

/// One deterministic step of the processing chain.
public protocol TextRule: Sendable {
    func apply(_ text: String, context: RuleContext) -> String
}
