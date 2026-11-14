import Foundation
import Testing
import ZackCore

@testable import BenchSupport

/// Returns the same recognition with words for every clip.
private struct WordTranscriber: Transcriber {
    let id = "words"
    let recognition: Recognition

    func transcribe(_ audio: AudioClip, hints: [String]) async throws -> String { recognition.text }
    func recognize(_ audio: AudioClip, hints: [String]) async throws -> Recognition { recognition }
}

@Test func wordsExportListsRuledWordsWithConfidence() async throws {
    let json = """
        {"vocabulary":["Merge Request"],"snippets":[],"cases":[
         {"id":"a","group":"prose","mode":"prose","spoken":"der Merge Request ist offen","expected":"","terms":[]},
         {"id":"b","group":"code","mode":"code","spoken":"der Merge Request ist offen","expected":"","terms":[]}]}
        """
    let directory = FileManager.default.temporaryDirectory.appending(path: "zack-words-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    for id in ["a", "b"] {
        try WAVFile.encode(AudioClip(samples: Array(repeating: 0.1, count: 1600)))
            .write(to: directory.appending(path: "\(id).wav"))
    }
    let words = [("äh", 0.3), ("der", 0.9), ("merge", 0.3), ("request", 0.3), ("ist", 0.9), ("offen", 0.9)]
        .map { RecognizedWord(text: $0.0, confidence: Float($0.1)) }
    let transcriber = WordTranscriber(
        recognition: Recognition(text: "äh der merge request ist offen", words: words))

    let cases = try await WordsExport.run(
        corpus: Corpus.decode(Data(json.utf8)), transcriber: transcriber, audioDirectory: directory,
        language: .german)

    #expect(cases.map(\.id) == ["a", "b"])
    #expect(cases[0].ruled == "der Merge Request ist offen")
    #expect(cases[0].eligible)
    #expect(!cases[1].eligible)
    #expect(
        cases[0].words == [
            WordEntry(text: "der", confidence: 0.9), WordEntry(text: "Merge", confidence: nil),
            WordEntry(text: "Request", confidence: nil), WordEntry(text: "ist", confidence: 0.9),
            WordEntry(text: "offen", confidence: 0.9),
        ])
}
