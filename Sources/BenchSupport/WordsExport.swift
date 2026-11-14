import Foundation
import ZackCore

/// A word of the rule text with the engine's confidence; nil where the word is never flagged.
struct WordEntry: Codable, Equatable {
    let text: String
    let confidence: Float?
}

/// One corpus case as the sense check would see it.
struct WordsCase: Codable, Equatable {
    let id: String
    let group: String
    let mode: TextMode
    let spoken: String
    let raw: String
    let ruled: String
    /// The sense check would look at this case: prose, no snippet, no signal word.
    let eligible: Bool
    let words: [WordEntry]
}

/// Recognizes every case with audio once and lists its rule words with their confidence.
enum WordsExport {
    static func run(corpus: Corpus, transcriber: any Transcriber, audioDirectory: URL, language: DictationLanguage)
        async throws -> [WordsCase]
    {
        try await transcriber.prepare()
        let vocabulary = corpus.parsedVocabulary
        let processor = TextProcessor(vocabulary: vocabulary, snippets: corpus.parsedSnippets)
        var cases: [WordsCase] = []
        for testCase in corpus.cases {
            let url = audioDirectory.appending(path: "\(testCase.id).wav")
            guard let data = try? Data(contentsOf: url), let clip = try? WAVFile.decode(data) else { continue }
            let recognition = try await transcriber.recognize(clip, hints: vocabulary.terms)
            let context = RuleContext(mode: testCase.mode, language: language)
            let ruled = processor.applyingRules(recognition.text, context: context)
            let words = SuspiciousWords.annotate(ruled, words: recognition.words, terms: vocabulary.terms)
                .filter(\.isWord).map { WordEntry(text: $0.text, confidence: $0.confidence) }
            cases.append(
                WordsCase(
                    id: testCase.id, group: testCase.group, mode: testCase.mode, spoken: testCase.spoken,
                    raw: recognition.text, ruled: ruled,
                    eligible: processor.checkApplies(recognition.text, context: context), words: words))
        }
        return cases
    }
}
