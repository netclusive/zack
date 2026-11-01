import Foundation
import Testing

@testable import ZackCore

/// One rule-chain result for a corpus case at a cursor context; a nil context is omitted from the JSON.
private struct GoldenEntry: Codable, Equatable {
    let id: String
    let context: String?
    let ruled: String
    let final: String
    let signal: Bool
}

private func goldenURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Golden/german-rules.json")
}

/// Pins the German rule output; set ZACK_WRITE_GOLDEN=1 to regenerate the file deliberately.
@Test func germanRulesMatchGolden() async throws {
    let corpus = try Corpus.decode(Data(contentsOf: corpusURL()))
    let processor = TextProcessor(vocabulary: corpus.parsedVocabulary, snippets: corpus.parsedSnippets)
    var actual: [GoldenEntry] = []
    for testCase in corpus.cases {
        for context in [nil, "und dann ", "Fertig. "] as [String?] {
            let result = await processor.process(
                testCase.spoken, context: RuleContext(mode: testCase.mode, textBeforeCursor: context))
            actual.append(
                GoldenEntry(
                    id: testCase.id, context: context, ruled: result.ruled, final: result.final,
                    signal: SignalWords.contains(result.ruled)))
        }
    }
    if ProcessInfo.processInfo.environment["ZACK_WRITE_GOLDEN"] == "1" {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(actual).write(to: goldenURL())
        return
    }
    let expected = try JSONDecoder().decode([GoldenEntry].self, from: Data(contentsOf: goldenURL()))
    #expect(actual.count == expected.count)
    for (actual, expected) in zip(actual, expected) {
        #expect(actual == expected, "\(expected.id) \(expected.context ?? "nil")")
    }
}
