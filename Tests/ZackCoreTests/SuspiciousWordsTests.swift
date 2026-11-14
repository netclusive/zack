import Testing

@testable import ZackCore

private func words(_ pairs: (String, Float)...) -> [RecognizedWord] {
    pairs.map { RecognizedWord(text: $0.0, confidence: $0.1) }
}

private func wordConfidences(_ segments: [WordSegment]) -> [Float?] {
    segments.filter(\.isWord).map(\.confidence)
}

@Test func confidenceLandsOnTheRuledWords() {
    let segments = SuspiciousWords.annotate(
        "Über Homeroot, ziehe ich GitLeaks.",
        words: words(("Über", 0.99), ("Homeroot,", 0.41), ("ziehe", 0.97), ("ich", 0.99), ("GitLeaks.", 0.9)),
        terms: [])
    #expect(wordConfidences(segments) == [0.99, 0.41, 0.97, 0.99, 0.9])
}

@Test func punctuationAndHyphenStayOnTheirWord() {
    let segments = SuspiciousWords.annotate(
        "Für das neue Faulan fehlt der DNS-Eintrag.",
        words: words(
            ("Für", 0.99), ("das", 0.98), ("neue", 0.97), ("Faulan", 0.35), ("fehlt", 0.96), ("der", 0.99),
            ("DNS-Eintrag.", 0.5)),
        terms: [])
    #expect(wordConfidences(segments) == [0.99, 0.98, 0.97, 0.35, 0.96, 0.99, 0.5])
    #expect(segments.filter(\.isWord).last?.text == "DNS-Eintrag")
}

@Test func removedFillerLeavesNoTrace() {
    let segments = SuspiciousWords.annotate(
        "Alles läuft.", words: words(("Äh,", 0.3), ("alles", 0.99), ("läuft.", 0.98)), terms: [])
    #expect(wordConfidences(segments) == [0.99, 0.98])
}

@Test func wordsChangedByRulesAreNeverSuspicious() {
    let segments = SuspiciousWords.annotate(
        "Das Update von Xcode", words: words(("Das", 0.99), ("Update", 0.98), ("von", 0.97), ("X-Code", 0.2)),
        terms: [])
    #expect(wordConfidences(segments) == [0.99, 0.98, 0.97, nil])
}

@Test func vocabularyTermsAreNeverSuspicious() {
    let segments = SuspiciousWords.annotate(
        "der Merge Request ist offen",
        words: words(("der", 0.9), ("Merge", 0.3), ("Request", 0.3), ("ist", 0.9), ("offen", 0.9)),
        terms: ["Merge Request"])
    #expect(wordConfidences(segments) == [0.9, nil, nil, 0.9, 0.9])
}

@Test func markingTakesWordsBelowTheThreshold() {
    let text = SuspiciousWords.marked(
        SuspiciousWords.annotate("eins zwei drei", words: words(("eins", 0.59), ("zwei", 0.6)), terms: []),
        below: 0.6)
    #expect(text.markedCount == 1)
    #expect(text.rendered() == "⟦eins⟧ zwei drei")
}

@Test func runsAreRenderedTogether() {
    let text = SuspiciousWords.marked(
        SuspiciousWords.annotate(
            "Den Bericht von Pierre Pistane schicke ich.",
            words: words(
                ("Den", 0.99), ("Bericht", 0.99), ("von", 0.98), ("Pierre", 0.3), ("Pistane", 0.2), ("schicke", 0.97),
                ("ich.", 0.99)),
            terms: []),
        below: 0.6)
    #expect(text.rendered() == "Den Bericht von ⟦Pierre Pistane⟧ schicke ich.")
    #expect(text.markedCount == 2)
}

@Test func runsBreakAtPunctuation() {
    let text = SuspiciousWords.marked(
        SuspiciousWords.annotate(
            "eins, zwei drei", words: words(("eins,", 0.1), ("zwei", 0.1), ("drei", 0.1)), terms: []),
        below: 0.6)
    #expect(text.rendered() == "⟦eins⟧, ⟦zwei drei⟧")
}

@Test func noWordsMarkNothing() {
    let text = SuspiciousWords.marked(SuspiciousWords.annotate("Alles gut.", words: [], terms: []), below: 0.6)
    #expect(text.markedCount == 0)
    #expect(text.rendered() == "Alles gut.")
}

@Test func splitKeepsTheText() {
    let text = "Hallo, Welt! readme.md -x"
    let segments = WordSegments.split(text)
    #expect(segments.map(\.text).joined() == text)
    #expect(segments.filter(\.isWord).map(\.text) == ["Hallo", "Welt", "readme.md", "x"])
}
