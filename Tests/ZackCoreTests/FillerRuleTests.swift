import Testing

@testable import ZackCore

@Test(arguments: [
    ("Äh, das Deployment läuft.", "Das Deployment läuft."),
    ("Das ist, äh, gut.", "Das ist gut."),
    ("Ähm wir mergen das. Äh, danach deployen wir.", "Wir mergen das. Danach deployen wir."),
    ("Wir treffen uns um zehn.", "Wir treffen uns um zehn."),
    ("Der Mähdrescher steht.", "Der Mähdrescher steht."),
    ("Hmm.", ""),
    ("Zeile eins, äh\nZeile zwei", "Zeile eins\nZeile zwei"),
])
func fillerRuleRemovesFillers(input: String, expected: String) {
    #expect(FillerRule().apply(input, context: RuleContext()) == expected)
}

@Test(arguments: [
    ("Äh. Ja.", "Ja."),
    ("Hm. Gut.", "Gut."),
    ("Ja. Äh. Gut.", "Ja. Gut."),
    ("Er sagte hm.", "Er sagte."),
    ("uh-oh", "uh-oh"),
    ("Hmm-Laut", "Hmm-Laut"),
])
func fillerRuleHandlesFillerOnlySentencesAndHyphens(input: String, expected: String) {
    #expect(FillerRule().apply(input, context: RuleContext()) == expected)
}

@Test(arguments: [
    ("Äh, äh. Ja.", "Ja."),
    ("Er sagte: hm. Ok.", "Er sagte. Ok."),
    ("Ja.  Äh. Gut.", "Ja. Gut."),
    ("Ja. Hm… Gut.", "Ja. Gut."),
    ("Gut.\nÄh.\nWeiter.", "Gut.\nWeiter."),
    ("Gut.\r\nÄh.\r\nWeiter.", "Gut.\r\nWeiter."),
    ("Ja? Hm! Gut.", "Ja? Gut."),
    ("Hm…", ""),
    ("Ähm, also, äh, ja.", "Also ja."),
    ("Äh", ""),
    ("Das ist äh gut.", "Das ist gut."),
    ("Äh, das ist gut.", "Das ist gut."),
    ("Er sagte hm.", "Er sagte."),
    ("uh-oh", "uh-oh"),
    ("Hmm-Laut", "Hmm-Laut"),
    (
        "Äh, die Abrechnung für Oktober ist noch nicht vollständig.",
        "Die Abrechnung für Oktober ist noch nicht vollständig."
    ),
    ("Ähm, ich bin ab nächster Woche im Urlaub.", "Ich bin ab nächster Woche im Urlaub."),
])
func fillerRuleCleansPunctuationLeftByRemovedFillers(input: String, expected: String) {
    #expect(FillerRule().apply(input, context: RuleContext()) == expected)
}
