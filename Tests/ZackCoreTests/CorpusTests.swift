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

func englishCorpusURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("bench/corpus/cases-en.json")
}

@Test func englishCorpusIsValid() throws {
    let corpus = try Corpus.decode(Data(contentsOf: englishCorpusURL()))
    #expect(corpus.cases.count == 44)
    #expect(Set(corpus.cases.map(\.id)).count == 44)
    let counts = Dictionary(grouping: corpus.cases, by: \.group).mapValues(\.count)
    #expect(counts == ["prose": 8, "terms": 8, "correction": 8, "code": 8, "vocabulary": 8, "long": 4])
    let prefixes = ["prose": "p", "terms": "t", "correction": "c", "code": "k", "vocabulary": "v", "long": "l"]
    for testCase in corpus.cases {
        #expect(testCase.id.hasPrefix(prefixes[testCase.group] ?? "?"), "\(testCase.id)")
        #expect((Metrics.termHitRate(terms: testCase.terms, in: testCase.expected) ?? 1) == 1, "\(testCase.id)")
        #expect(!testCase.spoken.contains("\u{2014}") && !testCase.expected.contains("\u{2014}"), "\(testCase.id)")
    }
    #expect(corpus.parsedVocabulary.terms == ["VMware", "GitHub", "SharePoint", "Kibana"])
    #expect(corpus.parsedSnippets.map(\.name) == ["signature", "callback"])
    let snippetCases = corpus.cases.filter {
        $0.group == "vocabulary" && $0.spoken.lowercased().hasPrefix("snippet ")
    }
    #expect(snippetCases.count >= 2)
    let long = corpus.cases.filter { $0.group == "long" }
    for testCase in long {
        // About 10 s of speech and no self-correction signal.
        #expect((25...28).contains(TextTools.words(testCase.spoken).count), "\(testCase.id)")
        #expect(!SignalWords.contains(testCase.spoken, language: .english), "\(testCase.id)")
    }
}

@Test func englishCorpusRulesProduceExpected() async throws {
    let corpus = try Corpus.decode(Data(contentsOf: englishCorpusURL()))
    let processor = TextProcessor(vocabulary: corpus.parsedVocabulary, snippets: corpus.parsedSnippets)
    for testCase in corpus.cases where testCase.group != "correction" {
        let result = await processor.process(
            testCase.spoken, context: RuleContext(mode: testCase.mode, language: .english))
        #expect(result.final == testCase.expected, "\(testCase.id)")
    }
}
