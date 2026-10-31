import Testing

@testable import ZackCore

@Test func wordsAreLowercasedWithoutPunctuation() {
    #expect(TextTools.words("Hallo, Welt! Das ist deploy.sh.") == ["hallo", "welt", "das", "ist", "deploy.sh"])
}

@Test func wordsKeepIdentifiers() {
    #expect(TextTools.words("Setz max_retry_count und user-id.") == ["setz", "max_retry_count", "und", "user-id"])
}

@Test(arguments: [
    ("Das  ist   gut .", "Das ist gut."),
    (" , Das ist gut", "Das ist gut"),
    ("Zeile eins\nZeile zwei", "Zeile eins\nZeile zwei"),
    ("Zeile eins \n Zeile zwei", "Zeile eins\nZeile zwei"),
    (" . ", ""),
])
func tidyCleansSpacing(input: String, expected: String) {
    #expect(TextTools.tidy(input) == expected)
}

@Test func fillersDoNotContainGermanWords() {
    #expect(!TextTools.fillers.contains("um"))
    #expect(TextTools.fillers.contains("ähm"))
}
