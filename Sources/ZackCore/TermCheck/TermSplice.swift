/// Takes another recognizer's words for the marked ranges of a text and keeps everything else.
public enum TermSplice {
    public struct Result: Sendable, Equatable {
        public let text: String
        /// Ranges whose words changed.
        public let replacedRuns: Int

        public init(text: String, replacedRuns: Int) {
            self.text = text
            self.replacedRuns = replacedRuns
        }
    }

    /// Each marked range takes the other text's words between its aligned neighbours, if those are 1 to n + 2 words
    /// for n marked words. Text start and end stand in for a missing neighbour only if the other side has a real one.
    public static func apply(_ marked: MarkedText, other: String) -> Result {
        let own = marked.segments
        let ownWords = own.indices.filter { own[$0].isWord }
        let otherSegments = WordSegments.split(other)
        let otherWords = otherSegments.indices.filter { otherSegments[$0].isWord }
        let pairs = SuspiciousWords.alignment(
            ownWords.map { own[$0].text.lowercased() }, otherWords.map { otherSegments[$0].text.lowercased() })
        let matchOf = Dictionary(uniqueKeysWithValues: pairs)

        var replacements: [(range: ClosedRange<Int>, segments: ArraySlice<WordSegment>)] = []
        for range in ranges(marked, words: ownWords) {
            let atStart = range.lowerBound == 0
            let atEnd = range.upperBound == ownWords.count - 1
            guard !(atStart && atEnd),
                let left = atStart ? -1 : matchOf[range.lowerBound - 1],
                let right = atEnd ? otherWords.count : matchOf[range.upperBound + 1],
                (1...(range.count + 2)).contains(right - left - 1)
            else { continue }
            let ownRange = ownWords[range.lowerBound]...ownWords[range.upperBound]
            let taken = otherSegments[otherWords[left + 1]...otherWords[right - 1]]
            guard taken.map(\.text) != own[ownRange].map(\.text) else { continue }
            replacements.append((ownRange, taken))
        }

        var segments = own
        for replacement in replacements.reversed() {
            segments.replaceSubrange(replacement.range, with: replacement.segments)
        }
        return Result(text: segments.map(\.text).joined(), replacedRuns: replacements.count)
    }

    /// Marked ranges with no unmarked word between them, each as its marked words without spaces.
    public static func focus(_ marked: MarkedText) -> [String] {
        let words = marked.segments.indices.filter { marked.segments[$0].isWord }
        return ranges(marked, words: words).map { range in
            words[range].map { marked.segments[$0].text }.joined()
        }
    }

    /// Positions in `words` of the marked words, grouped where no unmarked word lies between them.
    private static func ranges(_ marked: MarkedText, words: [Int]) -> [ClosedRange<Int>] {
        var ranges: [ClosedRange<Int>] = []
        var start: Int?
        for position in words.indices {
            if marked.marked.contains(words[position]) {
                start = start ?? position
            } else if let first = start {
                ranges.append(first...(position - 1))
                start = nil
            }
        }
        if let first = start { ranges.append(first...(words.count - 1)) }
        return ranges
    }
}
