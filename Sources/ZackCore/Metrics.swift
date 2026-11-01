public enum Metrics {
    /// Word error rate on compound-insensitive words (see `comparableWords`); filler words are ignored on both
    /// sides. The denominator is the reference length after hyphen splitting but before merging, so it does not
    /// depend on how the hypothesis spells a compound.
    public static func wordErrorRate(
        reference: String, hypothesis: String, language: DictationLanguage = .german
    ) -> Double {
        let fillers = language.pack.fillers
        let refWords = TextTools.words(reference).filter { !fillers.contains($0) }
        let (ref, hyp) = comparableWords(refWords, TextTools.words(hypothesis).filter { !fillers.contains($0) })
        let denominator = refWords.flatMap(hyphenParts).count
        guard denominator > 0 else { return hyp.isEmpty ? 0 : 1 }
        return Double(editDistance(ref, hyp)) / Double(denominator)
    }

    /// Share of terms found verbatim (case-sensitive) in the text; nil if there are no terms.
    public static func termHitRate(terms: [String], in text: String) -> Double? {
        guard !terms.isEmpty else { return nil }
        return Double(terms.filter { text.contains($0) }.count) / Double(terms.count)
    }

    /// True if both texts consist of the same compound-insensitive words (see `comparableWords`).
    public static func matches(expected: String, actual: String) -> Bool {
        let (left, right) = comparableWords(TextTools.words(expected), TextTools.words(actual))
        return left == right
    }

    /// Longest run of adjacent words merged into one compound.
    static let maxCompoundParts = 3

    /// Makes compound spelling irrelevant: hyphenated words are split into their parts, then adjacent words on
    /// one side are merged where their concatenation is a single word on the other side ("Support-Team",
    /// "Support Team" and "Supportteam" compare equal). Different words stay apart ("neue Router" is not
    /// "neuer Outer"). Known limits: a text that uses both spellings of the same compound can merge only
    /// partly; glued words such as "indem" and "in dem" count as equal; compounds of more than
    /// `maxCompoundParts` parts are not merged.
    static func comparableWords(_ a: [String], _ b: [String]) -> ([String], [String]) {
        let splitA = a.flatMap(hyphenParts)
        let splitB = b.flatMap(hyphenParts)
        return (merged(splitA, into: Set(splitB)), merged(splitB, into: Set(splitA)))
    }

    private static func hyphenParts(_ word: String) -> [String] {
        word.split(separator: "-").map(String.init)
    }

    /// Greedy, longest run first: merges up to `maxCompoundParts` adjacent words that form a word in `other`.
    private static func merged(_ words: [String], into other: Set<String>) -> [String] {
        var result: [String] = []
        var index = 0
        while index < words.count {
            let longest = min(maxCompoundParts, words.count - index)
            let length = stride(from: longest, to: 1, by: -1).first {
                other.contains(words[index..<index + $0].joined())
            }
            result.append(words[index..<index + (length ?? 1)].joined())
            index += length ?? 1
        }
        return result
    }

    /// Nearest-rank percentile, p in 0...100.
    public static func percentile(_ values: [Double], _ p: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = Int((p / 100 * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank - 1, 0), sorted.count - 1)]
    }

    static func editDistance(_ a: [String], _ b: [String]) -> Int {
        var previous = Array(0...b.count)
        for (i, left) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, right) in b.enumerated() {
                current[j + 1] = Swift.min(
                    previous[j + 1] + 1,
                    current[j] + 1,
                    previous[j] + (left == right ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
