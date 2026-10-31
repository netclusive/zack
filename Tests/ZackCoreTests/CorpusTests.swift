import Foundation
import Testing

@testable import ZackCore

@Test func decodesCorpus() throws {
    let json = """
        {"vocabulary": ["GitHub"], "snippets": ["Gruß => Viele Grüße"],
         "cases": [{"id": "p01", "group": "prose", "mode": "prose", "spoken": "Hallo.", "expected": "Hallo.", "terms": []}]}
        """
    let corpus = try Corpus.decode(Data(json.utf8))
    #expect(corpus.cases.first?.id == "p01")
    #expect(corpus.parsedVocabulary.terms == ["GitHub"])
    #expect(corpus.parsedSnippets == [Snippet(name: "Gruß", text: "Viele Grüße")])
}

@Test func repositoryCorpusIsValid() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("bench/corpus/cases.json")
    let corpus = try Corpus.decode(Data(contentsOf: url))
    #expect(corpus.cases.count == 44)
    #expect(Set(corpus.cases.map(\.id)).count == 44)
    #expect(Set(corpus.cases.map(\.group)) == ["prose", "dengl", "correction", "code", "vocabulary", "long"])
    for testCase in corpus.cases {
        #expect((Metrics.termHitRate(terms: testCase.terms, in: testCase.expected) ?? 1) == 1, "\(testCase.id)")
    }
    let long = corpus.cases.filter { $0.group == "long" }
    #expect(long.map(\.id) == ["l01", "l02", "l03", "l04"])
    for testCase in long {
        // About 10 s of speech and no self-correction signal, so the cleaner stays out of the timing.
        #expect((25...28).contains(TextTools.words(testCase.spoken).count), "\(testCase.id)")
        #expect(!SignalWords.contains(testCase.spoken), "\(testCase.id)")
    }
}
