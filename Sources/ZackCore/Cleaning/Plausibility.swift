/// Guards against a language model answering or expanding instead of cleaning.
public enum Plausibility {
    public static let maxLengthRatio = 1.1
    /// Corpus corrections keep at least 0.46 of the input length; 0.3 leaves margin.
    public static let minLengthRatio = 0.3
    public static let minKnownWordShare = 0.7

    public static func accept(input: String, output: String) -> Bool {
        let outputWords = TextTools.words(output)
        let ratio = Double(output.count) / Double(max(input.count, 1))
        guard !outputWords.isEmpty, ratio <= maxLengthRatio, ratio >= minLengthRatio else { return false }
        let inputWords = Set(TextTools.words(input))
        let known = outputWords.filter { inputWords.contains($0) }.count
        return Double(known) / Double(outputWords.count) >= minKnownWordShare
    }
}
