/// Instructions shared by all language-model cleaners.
public enum CleanerPrompt {
    public static func instructions(mode: TextMode, vocabulary: [String], language: DictationLanguage = .german)
        -> String
    {
        let text = language.pack.prompt
        var lines = text.rules
        if mode == .code {
            lines.append(text.codeHint)
        }
        if !vocabulary.isEmpty {
            // Labeled as a lookup: a bare list at the end was appended to the answer.
            lines.append(text.vocabularyLead + vocabulary.joined(separator: ", ") + text.vocabularyTail)
        }
        return lines.joined(separator: "\n")
    }

    /// Wraps untrusted dictation in the delimiters named by `instructions`.
    /// Every `<` becomes `‹` (single pass, cannot recombine), so no tag can occur inside the body;
    /// `>` is left alone, so "a > b" stays readable. Use `unescape` on the model output.
    public static func wrap(_ text: String, language: DictationLanguage = .german) -> String {
        let tag = language.pack.prompt.tag
        return "<\(tag)>\n\(text.replacingOccurrences(of: "<", with: "‹"))\n</\(tag)>"
    }

    /// Output token cap for every cleaner: cleaned text is about as long as the input, so twice the input tokens
    /// plus slack is generous while still stopping a model that answers or rambles.
    public static func maxOutputTokens(forInputTokens count: Int) -> Int {
        2 * max(count, 0) + 32
    }

    /// Reverses the `<` escaping of `wrap` on model output.
    public static func unescape(_ text: String) -> String {
        text.replacingOccurrences(of: "‹", with: "<")
    }
}
