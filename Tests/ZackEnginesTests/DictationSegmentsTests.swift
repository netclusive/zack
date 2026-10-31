import Testing

@testable import ZackApple

struct DictationSegmentsTests {
    @Test func volatileSegmentsAreJoinedInStartOrder() {
        var segments = DictationSegments()
        segments.addVolatile("zweiter Satz.", start: 5)
        segments.addVolatile("Erster Satz. ", start: 0)
        #expect(segments.text == "Erster Satz. zweiter Satz.")
    }

    @Test func laterVolatileResultReplacesEarlierOneWithSameStart() {
        var segments = DictationSegments()
        segments.addVolatile("Hallo Wel", start: 0)
        segments.addVolatile("Hallo Welt", start: 0)
        #expect(segments.text == "Hallo Welt")
    }

    @Test func finalTextComesBeforeVolatileText() {
        var segments = DictationSegments()
        segments.addFinal("Fertig. ")
        segments.addVolatile("offen", start: 3)
        #expect(segments.text == "Fertig. offen")
    }
}
