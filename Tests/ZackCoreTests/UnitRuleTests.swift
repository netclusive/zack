import Testing

@testable import ZackCore

@Test(arguments: [
    ("Das Kabel ist 5 Meter lang.", "Das Kabel ist 5 m lang."),
    ("Das Kabel ist fünf Meter lang.", "Das Kabel ist 5 m lang."),
    ("in 5 Metern Entfernung", "in 5 m Entfernung"),
    ("Die Festplatte hat 2TB.", "Die Festplatte hat 2 TB."),
    ("Die Festplatte hat zwei Terabyte.", "Die Festplatte hat 2 TB."),
    ("vier Gigabyte und zwölf Megabyte", "4 GB und 12 MB"),
    ("12.500 Megabyte", "12.500 MB"),
    ("Die Leitung schafft 100 Megabit pro Sekunde.", "Die Leitung schafft 100 Mbit/s."),
    ("hundert Megabit pro Sekunde", "100 Mbit/s"),
    ("1 Gigabit pro Sekunde", "1 Gbit/s"),
    ("50 Megabyte pro Sekunde", "50 MB/s"),
    ("100Mbit/s", "100 Mbit/s"),
    ("Das Netzteil liefert 600 Watt.", "Das Netzteil liefert 600 W."),
    ("48 Kilohertz", "48 kHz"),
    ("3,5 Gigahertz", "3,5 GHz"),
    ("3000 Kilowattstunden im Jahr", "3000 kWh im Jahr"),
    ("13,5%", "13,5 %"),
    ("13,5 Prozent", "13,5 %"),
    ("zehn Prozent", "10 %"),
    ("100%", "100 %"),
    ("20 Grad Celsius", "20 °C"),
    ("20°C", "20 °C"),
    ("100 Kilometer pro Stunde", "100 km/h"),
    ("5 Kilo Mehl", "5 kg Mehl"),
    ("2 Liter", "2 l"),
    ("80 Quadratmeter", "80 m²"),
    ("230 Volt und 16 Ampere", "230 V und 16 A"),
    ("5000 Milliamperestunden", "5000 mAh"),
    ("5 Meter pro Sekunde", "5 m pro Sekunde"),
])
func unitRuleWritesUnitSymbols(input: String, expected: String) {
    let rule = UnitRule()
    #expect(rule.apply(input, context: RuleContext()) == expected)
    #expect(rule.apply(expected, context: RuleContext()) == expected)
}

@Test(arguments: [
    "64 GB Arbeitsspeicher",
    "ein paar Gigabyte",
    "Gigabyte ist ein Hersteller.",
    "ein Gigabyte",
    "Das ist kilometerweit weg.",
    "in 5 Minuten",
    "nach 10 Sekunden",
    "zwei Stunden",
    "Draußen sind es 20 Grad.",
    "Das kostet 150 Euro.",
    "eine 100%ige Lösung",
    "ein 5-Meter-Kabel",
    "5 Meter-Kabel",
    "3 Prozentpunkte",
    "Meter für Meter",
])
func unitRuleLeavesOtherTextAlone(input: String) {
    #expect(UnitRule().apply(input, context: RuleContext()) == input)
}

@Test func unitRuleIsGermanOnly() {
    let input = "The disk has 2 Terabyte."
    #expect(UnitRule().apply(input, context: RuleContext(language: .english)) == input)
}

@Test(arguments: [
    ("Der Prozessor taktet mit drei Komma fünf Gigahertz.", "Der Prozessor taktet mit 3,5 GHz."),
    ("Die Quote liegt bei dreizehn Komma fünf Prozent.", "Die Quote liegt bei 13,5 %."),
    ("Wir verbrauchen dreitausend Kilowattstunden.", "Wir verbrauchen 3000 kWh."),
])
func unitsFollowNumbersInTheChain(input: String, expected: String) async {
    #expect(await TextProcessor().process(input, context: RuleContext()).final == expected)
}
