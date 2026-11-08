import Testing

@testable import ZackCore

@Test func parseReadsNamesTextAndNewlines() {
    let snippets = SnippetFile.parse(
        """
        # comment
        Gruß => Viele Grüße\\nMax Mustermann

        Rückruf => Ich melde mich heute noch telefonisch bei Ihnen.
        kaputt ohne Pfeil
        """)
    #expect(
        snippets == [
            Snippet(name: "Gruß", text: "Viele Grüße\nMax Mustermann"),
            Snippet(name: "Rückruf", text: "Ich melde mich heute noch telefonisch bei Ihnen."),
        ])
}

@Test(arguments: [
    "printf(\"%d\\n\", x)", "C:\\neu", "a\\\\b", "a\\\nb", "Ende\\", "\\", "Zeile 1\nZeile 2",
])
func typedBackslashSurvivesSavingAndReading(text: String) {
    let line = SnippetFormat.line(for: Snippet(name: "Code", text: text))
    #expect(SnippetFile.parse(line) == [Snippet(name: "Code", text: text)])
    guard case .entry(let entry) = SnippetFormat.kind(of: line) else {
        Issue.record("unreadable: \(line)")
        return
    }
    #expect(entry == Snippet(name: "Code", text: text))
}

@Test func handWrittenLinesKeepTheirMeaning() {
    #expect(
        SnippetFile.parse("Pfad => C:\\Users\\Max\nGruß => Viele Grüße\\nMax\n") == [
            Snippet(name: "Pfad", text: "C:\\Users\\Max"), Snippet(name: "Gruß", text: "Viele Grüße\nMax"),
        ])
}

@Test(arguments: [
    ("Baustein Gruß.", "Viele Grüße\nMax Mustermann"),
    ("baustein gruss", "Viele Grüße\nMax Mustermann"),
    ("Baustein unbekannt.", "Baustein unbekannt."),
    ("Der Baustein Gruß fehlt.", "Der Baustein Gruß fehlt."),
])
func snippetRuleReplacesWholeDictation(input: String, expected: String) {
    let rule = SnippetRule([Snippet(name: "Gruß", text: "Viele Grüße\nMax Mustermann")])
    #expect(rule.apply(input, context: RuleContext()) == expected)
}

@Test(arguments: ["Baustein Gruesse", "Baustein Grüße", "baustein gruesse.", "Baustein GRÜSSE"])
func snippetNamesFoldUmlauts(input: String) {
    let rule = SnippetRule([Snippet(name: "Grüße", text: "Viele Grüße")])
    #expect(rule.apply(input, context: RuleContext()) == "Viele Grüße")
}

@Test func englishSnippetMatchesWithCaseAndPunctuation() {
    let rule = SnippetRule([Snippet(name: "signature", text: "Best regards\nJane Doe")])
    #expect(rule.match("Snippet signature.", language: .english) == "Best regards\nJane Doe")
    #expect(rule.match("Baustein signature", language: .english) == nil)
    #expect(rule.match("snippet signature", language: .german) == nil)
}
