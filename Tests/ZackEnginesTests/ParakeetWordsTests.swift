import FluidAudio
import Testing
import ZackCore

@testable import ZackParakeet

private func timing(_ token: String, _ confidence: Float) -> TokenTiming {
    TokenTiming(token: token, tokenId: 0, startTime: 0, endTime: 0, confidence: confidence)
}

@Test func tokensGroupIntoWordsWithTheirLowestConfidence() {
    let timings = [
        timing(" Über", 0.99), timing(" Hom", 0.9), timing("e", 0.4), timing("root", 0.8), timing(",", 0.95),
        timing(" zie", 0.99), timing("he", 0.97),
    ]
    #expect(
        ParakeetWords.group(timings) == [
            RecognizedWord(text: "Über", confidence: 0.99), RecognizedWord(text: "Homeroot,", confidence: 0.4),
            RecognizedWord(text: "ziehe", confidence: 0.97),
        ])
}

@Test func blanksAndEmptyTokensAreSkipped() {
    let timings = [
        timing(" Al", 0.9), timing("<blank>", 0.1), timing("les", 0.8), timing("", 0.2), timing(" gut", 0.95),
        timing("<pad>", 0.05),
    ]
    #expect(
        ParakeetWords.group(timings) == [
            RecognizedWord(text: "Alles", confidence: 0.8), RecognizedWord(text: "gut", confidence: 0.95),
        ])
}

@Test func sentencePieceMarkerStartsAWord() {
    let timings = [timing("▁Über", 0.99), timing("▁Hom", 0.5), timing("ebrew", 0.7)]
    #expect(
        ParakeetWords.group(timings) == [
            RecognizedWord(text: "Über", confidence: 0.99), RecognizedWord(text: "Homebrew", confidence: 0.5),
        ])
}

@Test func noTimingsGiveNoWords() {
    #expect(ParakeetWords.group([]).isEmpty)
}
