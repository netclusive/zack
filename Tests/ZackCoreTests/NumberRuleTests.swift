import Testing

@testable import ZackCore

@Test(arguments: [
    ("Die Datei hat zweihundertsechsundvierzig Zeilen.", "Die Datei hat 246 Zeilen."),
    ("Es waren fünftausend Teilnehmer.", "Es waren 5000 Teilnehmer."),
    ("Fünftausend Teilnehmer kamen.", "5000 Teilnehmer kamen."),
    ("im Jahr zweitausendsechsundzwanzig", "im Jahr 2026"),
    ("Das Haus wurde neunzehnhundertneunundneunzig gebaut.", "Das Haus wurde 1999 gebaut."),
    ("Das Budget liegt bei zwölftausendfünfhundert Euro.", "Das Budget liegt bei 12.500 Euro."),
    ("Wir haben dreihunderttausend Besucher gezählt.", "Wir haben 300.000 Besucher gezählt."),
    ("Das kostet einhundertfünfzig Euro.", "Das kostet 150 Euro."),
    ("Wir sind dreiundzwanzig Leute.", "Wir sind 23 Leute."),
    ("dreizehn", "13"),
    ("um vierzehn Uhr", "um 14 Uhr"),
    // Parakeet sometimes splits one number into two words.
    ("Die Datei hat fünftausend zweihundertsechsundvierzig Zeilen.", "Die Datei hat 5246 Zeilen."),
    ("fünftausend zweihundert sechsundvierzig", "5246"),
    ("im Jahr zweitausend sechsundzwanzig", "im Jahr 2026"),
    ("neunzehnhundert neunundneunzig", "1999"),
    ("hundert zwanzig Seiten", "120 Seiten"),
    ("3,5 fünftausend zweihundertsechsundvierzig Fünftausend", "3,5 5246 5000"),
    // Decimals are digits whatever their size.
    ("drei Komma fünf", "3,5"),
    ("dreizehn Komma fünf Prozent", "13,5 Prozent"),
    ("null Komma zwei fünf", "0,25"),
    ("drei Komma fünfundzwanzig", "3,25"),
    ("3 Komma 5", "3,5"),
])
func numberRuleWritesNumbersFromThirteenInDigits(input: String, expected: String) {
    let rule = NumberRule()
    #expect(rule.apply(input, context: RuleContext()) == expected)
    #expect(rule.apply(expected, context: RuleContext()) == expected)
}

@Test(arguments: [
    "Wir brauchen vier neue Laptops.",
    "Das dauert zwölf Monate.",
    "Tausend Dank!",
    "Das habe ich dir hundert Mal gesagt.",
    "Hunderte von Menschen kamen.",
    "Am zwanzigsten Mai.",
    "Die Zwanzigjährige kommt.",
    "Ich bin hundertprozentig sicher.",
    "ein ganzes Jahrhundert",
    "ein zwanzig-seitiger Bericht",
    "Das kostet 12.500 Euro.",
    "Ich habe drei Komma gesetzt.",
    "elf und zwölf",
    "um 16:45 Uhr",
])
func numberRuleLeavesOtherTextAlone(input: String) {
    #expect(NumberRule().apply(input, context: RuleContext()) == input)
}

@Test func numberRuleIsGermanOnly() {
    let input = "Wir sind dreiundzwanzig Leute."
    #expect(NumberRule().apply(input, context: RuleContext(language: .english)) == input)
}

@Test func numbersFromThirteenAreDigitsInTheChain() async {
    let result = await TextProcessor().process("Es kamen fünftausend Besucher.", context: RuleContext())
    #expect(result.final == "Es kamen 5000 Besucher.")
}
