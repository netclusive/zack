import Testing

@testable import ZackCore

@Test(arguments: [
    ("Setz camel case user id auf null.", "Setz userId auf null."),
    ("Öffne deploy Punkt sh.", "Öffne deploy.sh"),
    ("Setz snake case max retry count, dann weiter.", "Setz max_retry_count, dann weiter."),
    ("kebab case user id in der Datei ändern", "user-id in der Datei ändern"),
    ("Pascalcase payment service.", "PaymentService"),
    ("Camel Case User ID.", "userId"),
    ("Lies die Datei readme Punkt md und fass sie zusammen.", "Lies die Datei readme.md und fass sie zusammen."),
    ("Bitte prüf die Logs auf dem Server.", "Bitte prüf die Logs auf dem Server."),
    ("Git Status.", "Git Status"),
])
func codeModeRewritesIdentifiers(input: String, expected: String) {
    #expect(CodeModeRule().apply(input, context: RuleContext(mode: .code)) == expected)
}

@Test func proseModeIsUntouched() {
    let input = "Setz camel case user id auf null."
    #expect(CodeModeRule().apply(input, context: RuleContext(mode: .prose)) == input)
}

@Test(arguments: [
    "Ich mache das camel case mäßig",
    "Das ist ein snake case Problem",
    "Ich nutze camelcase heute",
])
func codeModeKeepsProseWithSingleWordAfterCommand(input: String) {
    #expect(CodeModeRule().apply(input, context: RuleContext(mode: .code)) == input)
}

@Test(arguments: [
    ("Open the file readme dot md and summarize it.", "Open the file readme.md and summarize it."),
    ("Set snake case max retry count in the config file.", "Set max_retry_count in the config file."),
    ("camel case user id", "userId"),
])
func englishCodeModeRewritesIdentifiers(input: String, expected: String) {
    #expect(CodeModeRule().apply(input, context: RuleContext(mode: .code, language: .english)) == expected)
}
