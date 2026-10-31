import Testing

@testable import ZackCore

@Test(arguments: [
    ("", "das läuft.", "Das läuft."),
    ("Wir haben es geprüft. ", "der Test läuft.", "Der Test läuft."),
    ("Ich glaube,", "Der Server läuft.", " der Server läuft."),
    ("Ich glaube ", "Server laufen wieder.", "Server laufen wieder."),
    ("Zeile\n", "das passt.", "Das passt."),
    ("Hallo (", "Test", "Test"),
    ("Ich sehe", "API ist down.", " API ist down."),
])
func cursorJoinAdaptsToTextBefore(before: String, text: String, expected: String) {
    let rule = CursorJoinRule()
    #expect(rule.apply(text, context: RuleContext(textBeforeCursor: before)) == expected)
}

@Test func withoutCursorContextTextIsUnchanged() {
    #expect(CursorJoinRule().apply("der Test.", context: RuleContext()) == "der Test.")
}

@Test(arguments: [
    ("Hallo.\n  ", "und", "Und"),
    ("Hallo.\r\n", "und", "Und"),
    ("foo\n    ", "bar", "Bar"),
])
func cursorJoinDetectsLineStartAfterIndentationAndCRLF(before: String, text: String, expected: String) {
    #expect(CursorJoinRule().apply(text, context: RuleContext(textBeforeCursor: before)) == expected)
}

@Test(arguments: [
    (#"Er sagte "Hallo""#, "und ging", " und ging"),
    (#"Er sagte ""#, "API ist down", "API ist down"),
    ("Er sagte 'Hallo'", "und ging", " und ging"),
    ("Er sagte '", "API ist down", "API ist down"),
    ("Es geht's gut. Er sagte '", "ja", "ja"),
    ("It's what he called 'the thing'", "fine", " fine"),
    ("it's", "fine", " fine"),
    ("Er sagte „", "API ist down", "API ist down"),
    ("Er sagte „Hallo“", "und ging", " und ging"),
])
func cursorJoinTellsOpeningFromClosingQuotes(before: String, text: String, expected: String) {
    #expect(CursorJoinRule().apply(text, context: RuleContext(textBeforeCursor: before)) == expected)
}

@Test(arguments: [
    ("cd ~/", "src", "src"),
    ("foo-", "bar", "bar"),
    ("a/", "b", "b"),
    ("x=", "1", "1"),
    ("a\\", "b", "b"),
    ("user@", "host", "host"),
    ("cd src", "bar", " bar"),
    ("Ende.", "Text", " Text"),
    ("Hinweis:", "text", " text"),
    ("self.", "name", " Name"),
    ("key:", "value", " value"),
])
func cursorJoinAddsNoSpaceAfterPathAndOperatorCharactersInCodeMode(before: String, text: String, expected: String) {
    let context = RuleContext(mode: .code, textBeforeCursor: before)
    #expect(CursorJoinRule().apply(text, context: context) == expected)
}

@Test func cursorJoinKeepsSpaceAfterOperatorCharactersInProse() {
    #expect(CursorJoinRule().apply("bar", context: RuleContext(textBeforeCursor: "foo-")) == " bar")
}
