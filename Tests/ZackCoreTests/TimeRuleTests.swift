import Testing

@testable import ZackCore

@Test(arguments: [
    ("Wir treffen uns um 16.45 Uhr.", "Wir treffen uns um 16:45 Uhr."),
    ("16.45 Uhr 17.38 Uhr 12.15 Uhr", "16:45 Uhr 17:38 Uhr 12:15 Uhr"),
    ("um 8.30 Uhr", "um 8:30 Uhr"),
    ("um 08.30 Uhr", "um 08:30 Uhr"),
    ("um 0.15 Uhr", "um 0:15 Uhr"),
    ("Von 14.30 Uhr bis 15.40 Uhr bin ich weg.", "Von 14:30 bis 15:40 Uhr bin ich weg."),
    ("von vierzehn Uhr dreißig bis fünfzehn Uhr vierzig", "von 14:30 bis 15:40 Uhr"),
    ("Sechzehn Uhr fünfundvierzig passt.", "16:45 Uhr passt."),
    ("um acht Uhr dreißig", "um 8:30 Uhr"),
    ("um ein Uhr fünf", "um 1:05 Uhr"),
    ("um null Uhr fünfzehn", "um 0:15 Uhr"),
    ("um sechzehn Uhr null fünf", "um 16:05 Uhr"),
    ("um 16 Uhr 45", "um 16:45 Uhr"),
    ("um 8 Uhr dreißig", "um 8:30 Uhr"),
    ("um siebzehn Uhr 5", "um 17:05 Uhr"),
    ("um sechzehn Uhr fünfundvierzig, dann", "um 16:45 Uhr, dann"),
    ("um sechzehn Uhr fünfundvierzig und danach", "um 16:45 Uhr und danach"),
    ("um sechzehn Uhr fünfundvierzig\nZweite Zeile", "um 16:45 Uhr\nZweite Zeile"),
])
func timeRuleWritesTimesWithAColon(input: String, expected: String) {
    let rule = TimeRule()
    #expect(rule.apply(input, context: RuleContext()) == expected)
    #expect(rule.apply(expected, context: RuleContext()) == expected)
}

@Test(arguments: [
    "um 16:45 Uhr",
    "um sechzehn Uhr",
    "Um zehn Uhr kommen drei Personen.",
    "um zehn Uhr drei Personen",
    "um zehn Uhr fünf Minuten später",
    "um halb acht",
    "Das kostet 16.45 Euro.",
    "um 25.30 Uhr",
    "um 16.75 Uhr",
    "die Uhr zehn",
    "Bis 16 Uhr ist offen.",
])
func timeRuleLeavesOtherTextAlone(input: String) {
    #expect(TimeRule().apply(input, context: RuleContext()) == input)
}

@Test func timeRuleIsGermanOnly() {
    let input = "Meet me at 16.45 Uhr."
    #expect(TimeRule().apply(input, context: RuleContext(language: .english)) == input)
}

@Test func timeRuleAppliesInCodeMode() {
    #expect(TimeRule().apply("Deploy um 16.45 Uhr", context: RuleContext(mode: .code)) == "Deploy um 16:45 Uhr")
}
