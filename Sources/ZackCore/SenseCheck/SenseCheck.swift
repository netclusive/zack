/// The sense check flags words the engine was unsure about; a language model may replace those that make no sense.
public enum SenseCheck {
    /// Longest text before the cursor given to the model as context.
    public static let maxContextCharacters = 400
    /// Marks around flagged words in the text the model gets.
    public static let openMark = "⟦"
    public static let closeMark = "⟧"
}
