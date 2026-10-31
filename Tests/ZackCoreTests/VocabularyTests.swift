import Testing

@testable import ZackCore

@Test func parseReadsTermsAndReplacements() {
    let vocabulary = VocabularyFile.parse(
        """
        # comment
        VMware
        git hub => GitHub
        GitHub
        """)
    #expect(vocabulary.terms == ["VMware", "GitHub"])
    #expect(vocabulary.replacements == [Vocabulary.Replacement(from: "git hub", to: "GitHub")])
}

@Test(arguments: [
    ("Das läuft auf vmware.", "Das läuft auf VMware."),
    ("Push nach git hub.", "Push nach GitHub."),
    ("Push nach Git Hub, dann weiter.", "Push nach GitHub, dann weiter."),
    ("Das ist digital.", "Das ist digital."),
    ("Wir nutzen K8s.", "Wir nutzen K8s."),
])
func vocabularyRuleFixesSpelling(input: String, expected: String) {
    let vocabulary = VocabularyFile.parse("VMware\nGit\nK8s\ngit hub => GitHub")
    #expect(VocabularyRule(vocabulary).apply(input, context: RuleContext()) == expected)
}

@Test func replacementTemplateCharactersStayLiteral() {
    let vocabulary = Vocabulary(replacements: [.init(from: "preis", to: "$1 und \\n")])
    #expect(VocabularyRule(vocabulary).apply("Der preis.", context: RuleContext()) == "Der $1 und \\n.")
}
