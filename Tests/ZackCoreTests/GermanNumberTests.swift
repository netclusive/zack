import Testing

@testable import ZackCore

@Test(arguments: [
    ("null", 0), ("eins", 1), ("zwei", 2), ("zwölf", 12), ("dreizehn", 13), ("sechzehn", 16), ("siebzehn", 17),
    ("zwanzig", 20), ("einundzwanzig", 21), ("dreißig", 30), ("dreissig", 30), ("fünfundvierzig", 45),
    ("neunundneunzig", 99), ("hundert", 100), ("einhundert", 100), ("hunderteins", 101), ("einhundertfünfzig", 150),
    ("zweihundertsechsundvierzig", 246), ("tausend", 1000), ("fünftausend", 5000), ("Fünftausend", 5000),
    ("fünftausendzweihundertsechsundvierzig", 5246), ("zweitausendsechsundzwanzig", 2026),
    ("neunzehnhundertneunundneunzig", 1999), ("zwölftausendfünfhundert", 12500), ("dreihunderttausend", 300_000),
    ("neunhundertneunundneunzigtausendneunhundertneunundneunzig", 999_999),
])
func germanNumberReadsNumberWords(word: String, value: Int) {
    #expect(GermanNumber.value(of: word) == value)
}

@Test(arguments: [
    "ein", "und", "Uhr", "zwanzigste", "Zwanzigjährige", "hundertprozentig", "Hunderte", "Tausende", "Jahrhundert",
    "Jahrtausend", "siebenzehn", "sechszig", "hundertein", "einszwanzig", "zweiundzwölf", "tausendtausend",
    "neunzehnhunderttausend", "",
])
func germanNumberRejectsOtherWords(word: String) {
    #expect(GermanNumber.value(of: word) == nil)
}
