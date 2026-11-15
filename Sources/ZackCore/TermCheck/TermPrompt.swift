/// Chooses the vocabulary terms the second recognizer gets as its prompt.
public enum TermPrompt {
    /// WhisperKit keeps only the last `maxTokenContext / 2 - 1` prompt tokens (TextDecoder.swift:199-200, 1.1.1).
    public static let tokenBudget = 111

    /// All terms if `tokens(terms) <= budget`; otherwise terms by falling similarity to `focus` (ties in list order),
    /// each taken if it still fits; result in list order.
    public static func select(
        _ terms: [String], focus: [String], budget: Int = tokenBudget, tokens: ([String]) -> Int
    ) -> [String] {
        guard tokens(terms) > budget else { return terms }
        let scores = terms.map { term in focus.map { similarity(term, $0) }.max() ?? 0 }
        let byScore = terms.indices.sorted { scores[$0] > scores[$1] || (scores[$0] == scores[$1] && $0 < $1) }
        var chosen: [Int] = []
        for index in byScore {
            let candidate = (chosen + [index]).sorted()
            if tokens(candidate.map { terms[$0] }) <= budget { chosen = candidate }
        }
        return chosen.map { terms[$0] }
    }

    /// 1 minus the Levenshtein distance of the lowercased letters and digits, divided by the longer length.
    static func similarity(_ a: String, _ b: String) -> Double {
        let x = normalized(a)
        let y = normalized(b)
        let longer = max(x.count, y.count)
        guard longer > 0 else { return 0 }
        return 1 - Double(distance(x, y)) / Double(longer)
    }

    private static func normalized(_ text: String) -> [Character] {
        Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
    }

    private static func distance(_ a: [Character], _ b: [Character]) -> Int {
        guard !a.isEmpty else { return b.count }
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for (j, y) in b.enumerated() {
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1))
            }
            previous = current
        }
        return previous[b.count]
    }
}
