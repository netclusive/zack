import Testing

@testable import ZackCore

/// Marks the word segments of `text` whose text is in `words`.
private func marking(_ text: String, _ words: Set<String>) -> MarkedText {
    let segments = WordSegments.split(text)
    let marked = segments.indices.filter { segments[$0].isWord && words.contains(segments[$0].text) }
    return MarkedText(segments: segments, marked: Set(marked))
}

@Test func markedWordTakesTheWordBetweenMatchingNeighbours() {
    let result = TermSplice.apply(marking("ich nutze Homeroot dafür", ["Homeroot"]), other: "ich nutze Homebrew dafür")
    #expect(result == TermSplice.Result(text: "ich nutze Homebrew dafür", replacedRuns: 1))
}

@Test func unmarkedWordsStayWhenTheOtherTextDiffers() {
    let result = TermSplice.apply(
        marking("kurze Downtime für Homeroot.", ["Homeroot"]), other: "kurze NetBox für Homebrew.")
    #expect(result.text == "kurze Downtime für Homebrew.")
    #expect(result.replacedRuns == 1)
}

@Test func rangeStaysWhenANeighbourDoesNotAlign() {
    let result = TermSplice.apply(marking("a b c d", ["c"]), other: "a x y d")
    #expect(result == TermSplice.Result(text: "a b c d", replacedRuns: 0))
}

@Test func twoMarkedWordsMayBecomeOne() {
    let result = TermSplice.apply(
        marking("Den Bericht von Pierre Pistane schicke ich", ["Pierre", "Pistane"]),
        other: "Den Bericht von PHPStan schicke ich")
    #expect(result == TermSplice.Result(text: "Den Bericht von PHPStan schicke ich", replacedRuns: 1))
}

@Test func runsSplitByACommaFormOneRange() {
    let result = TermSplice.apply(
        marking("Server im Homeroot, Faulan läuft.", ["Homeroot", "Faulan"]), other: "Server im Homebrew, VLAN läuft.")
    #expect(result == TermSplice.Result(text: "Server im Homebrew, VLAN läuft.", replacedRuns: 1))
}

@Test func rangeStaysBeyondTwoExtraWords() {
    let result = TermSplice.apply(marking("a b c", ["b"]), other: "a w x y z c")
    #expect(result == TermSplice.Result(text: "a b c", replacedRuns: 0))
}

@Test func rangeMayNotVanish() {
    let result = TermSplice.apply(marking("a b c", ["b"]), other: "a c")
    #expect(result == TermSplice.Result(text: "a b c", replacedRuns: 0))
}

@Test func rangeAtTheEndKeepsTheOwnFinalMark() {
    let result = TermSplice.apply(marking("das ist Faulan.", ["Faulan"]), other: "das ist VLAN!")
    #expect(result == TermSplice.Result(text: "das ist VLAN.", replacedRuns: 1))
}

@Test func rangeAtTheStartTakesTheFirstWords() {
    let result = TermSplice.apply(marking("Homeroot ist da.", ["Homeroot"]), other: "Homebrew ist da.")
    #expect(result == TermSplice.Result(text: "Homebrew ist da.", replacedRuns: 1))
}

@Test func rangeWithoutARealNeighbourStays() {
    let single = TermSplice.apply(marking("Homeroot.", ["Homeroot"]), other: "Vielen Dank.")
    #expect(single == TermSplice.Result(text: "Homeroot.", replacedRuns: 0))
    let pair = TermSplice.apply(marking("Pierre Pistane", ["Pierre", "Pistane"]), other: "PHPStan")
    #expect(pair == TermSplice.Result(text: "Pierre Pistane", replacedRuns: 0))
}

/// Whisper invents short sentences ("Vielen Dank.") at the edges of a recording; text start or end as the anchor
/// must not let such a sentence into the dictation.
@Test func sentenceAppendedAfterAnEndRangeIsNotTaken() {
    let result = TermSplice.apply(marking("das ist Faulan.", ["Faulan"]), other: "das ist VLAN. Vielen Dank.")
    #expect(result == TermSplice.Result(text: "das ist Faulan.", replacedRuns: 0))
}

@Test func sentencePrependedBeforeAStartRangeIsNotTaken() {
    let result = TermSplice.apply(marking("Homeroot ist da.", ["Homeroot"]), other: "Danke. Homebrew ist da.")
    #expect(result == TermSplice.Result(text: "Homeroot ist da.", replacedRuns: 0))
}

@Test func sentenceBreakInsideAMiddleRangeIsNotTaken() {
    let result = TermSplice.apply(
        marking("ich nutze Homeroot dafür", ["Homeroot"]), other: "ich nutze Home. Brew dafür")
    #expect(result == TermSplice.Result(text: "ich nutze Homeroot dafür", replacedRuns: 0))
}

@Test func sentenceBreakTheRangeAlreadyHasMayStay() {
    let result = TermSplice.apply(
        marking("Server im Homeroot. Faulan läuft.", ["Homeroot", "Faulan"]),
        other: "Server im Homebrew. VLAN läuft.")
    #expect(result == TermSplice.Result(text: "Server im Homebrew. VLAN läuft.", replacedRuns: 1))
}

@Test func sameWordsAreNoReplacement() {
    let text = "Über Homeroot ziehe ich gitleaks."
    let result = TermSplice.apply(marking(text, ["Homeroot"]), other: text)
    #expect(result == TermSplice.Result(text: text, replacedRuns: 0))
}

@Test func emptyOrInventedOtherTextKeepsTheText() {
    let text = "Über Homeroot ziehe ich gitleaks."
    for other in ["", "Vielen Dank."] {
        let result = TermSplice.apply(marking(text, ["Homeroot"]), other: other)
        #expect(result == TermSplice.Result(text: text, replacedRuns: 0))
    }
}

@Test func withoutMarksTheTextStays() {
    let result = TermSplice.apply(marking("Alles läuft.", []), other: "Alles lief.")
    #expect(result == TermSplice.Result(text: "Alles läuft.", replacedRuns: 0))
}

@Test func focusJoinsTheWordsOfARange() {
    #expect(TermSplice.focus(marking("von Pierre Pistane schicke", ["Pierre", "Pistane"])) == ["PierrePistane"])
    #expect(TermSplice.focus(marking("im Homeroot, Faulan läuft", ["Homeroot", "Faulan"])) == ["HomerootFaulan"])
    #expect(TermSplice.focus(marking("a b c d", ["a", "c"])) == ["a", "c"])
}
