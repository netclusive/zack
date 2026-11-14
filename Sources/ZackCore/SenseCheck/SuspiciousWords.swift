/// The rule text with the words to check marked.
public struct MarkedText: Sendable, Equatable {
    public let segments: [WordSegment]
    /// Indices into `segments` of the marked words.
    public let marked: Set<Int>

    public init(segments: [WordSegment], marked: Set<Int>) {
        self.segments = segments
        self.marked = marked
    }

    public var markedCount: Int { marked.count }

    /// Segment ranges of marked words that only whitespace separates; each is one run for the model.
    public var runs: [ClosedRange<Int>] {
        var runs: [ClosedRange<Int>] = []
        var index = 0
        while index < segments.count {
            guard marked.contains(index) else {
                index += 1
                continue
            }
            var end = index
            while end + 2 < segments.count, marked.contains(end + 2),
                segments[end + 1].text.allSatisfy(\.isWhitespace)
            {
                end += 2
            }
            runs.append(index...end)
            index = end + 1
        }
        return runs
    }

    /// The text with each run between `SenseCheck.openMark` and `SenseCheck.closeMark`.
    public func rendered() -> String {
        var starts: [Int: Int] = [:]
        for run in runs { starts[run.lowerBound] = run.upperBound }
        var result = ""
        var index = 0
        while index < segments.count {
            if let end = starts[index] {
                result += SenseCheck.openMark + segments[index...end].map(\.text).joined() + SenseCheck.closeMark
                index = end + 1
            } else {
                result += segments[index].text
                index += 1
            }
        }
        return result
    }
}

public enum SuspiciousWords {
    /// Puts the engine's confidence on the words of the rule text. Recognized and rule words are aligned in order,
    /// ignoring case, so words the rules removed, changed or added get none; words of a vocabulary term get none.
    public static func annotate(_ ruled: String, words: [RecognizedWord], terms: [String]) -> [WordSegment] {
        var segments = WordSegments.split(ruled)
        let wordIndices = segments.indices.filter { segments[$0].isWord }
        let ruledWords = wordIndices.map { segments[$0].text.lowercased() }
        let recognized = words.flatMap { word in TextTools.words(word.text).map { ($0, word.confidence) } }
        for (ruledIndex, recognizedIndex) in alignment(ruledWords, recognized.map(\.0)) {
            segments[wordIndices[ruledIndex]].confidence = recognized[recognizedIndex].1
        }
        for term in terms {
            let parts = TextTools.words(term)
            guard !parts.isEmpty, parts.count <= ruledWords.count else { continue }
            for start in 0...(ruledWords.count - parts.count)
            where ruledWords[start..<(start + parts.count)].elementsEqual(parts) {
                for offset in 0..<parts.count { segments[wordIndices[start + offset]].confidence = nil }
            }
        }
        return segments
    }

    /// Marks every word whose confidence lies below `threshold`.
    public static func marked(_ segments: [WordSegment], below threshold: Float) -> MarkedText {
        let marked = segments.indices.filter { index in
            segments[index].confidence.map { $0 < threshold } ?? false
        }
        return MarkedText(segments: segments, marked: Set(marked))
    }

    /// Index pairs of a longest common subsequence of `a` and `b`.
    static func alignment(_ a: [String], _ b: [String]) -> [(Int, Int)] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var lengths = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                lengths[i][j] = a[i] == b[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var pairs: [(Int, Int)] = []
        var i = 0
        var j = 0
        while i < a.count, j < b.count {
            if a[i] == b[j] {
                pairs.append((i, j))
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return pairs
    }
}
