import Foundation

public struct CorpusCase: Codable, Sendable, Equatable {
    public let id: String
    /// prose, dengl, correction, code, vocabulary or long (about 10 s clips for the latency target)
    public let group: String
    public let mode: TextMode
    /// Text to read aloud, verbatim; reference for the word error rate.
    public let spoken: String
    /// Expected text after processing.
    public let expected: String
    /// Terms that must appear verbatim in the final text.
    public let terms: [String]
}

public struct Corpus: Codable, Sendable {
    /// Lines in vocabulary.txt format.
    public let vocabulary: [String]
    /// Lines in snippets.txt format.
    public let snippets: [String]
    public let cases: [CorpusCase]

    public static func decode(_ data: Data) throws -> Corpus {
        try JSONDecoder().decode(Corpus.self, from: data)
    }

    public var parsedVocabulary: Vocabulary { VocabularyFile.parse(vocabulary.joined(separator: "\n")) }
    public var parsedSnippets: [Snippet] { SnippetFile.parse(snippets.joined(separator: "\n")) }
}
