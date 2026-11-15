import Testing

@testable import ZackCore

/// Ten tokens per term.
private func perTerm(_ terms: [String]) -> Int { terms.count * 10 }

/// One token per character.
private func perCharacter(_ terms: [String]) -> Int { terms.reduce(0) { $0 + $1.count } }

@Test func allTermsWhenTheyFit() {
    let terms = ["GitLab", "Homebrew", "Proxmox"]
    #expect(TermPrompt.select(terms, focus: ["Homeroot"], budget: 111, tokens: perTerm) == terms)
}

@Test func mostSimilarTermFirstWhenTheBudgetIsShort() {
    let selected = TermPrompt.select(
        ["GitLab", "Homebrew", "Proxmox"], focus: ["Homeroot"], budget: 10, tokens: perTerm)
    #expect(selected == ["Homebrew"])
}

@Test func resultKeepsListOrder() {
    let selected = TermPrompt.select(
        ["GitLab", "Homebrew", "Proxmox"], focus: ["Proxmocks", "Homeroot"], budget: 20, tokens: perTerm)
    #expect(selected == ["Homebrew", "Proxmox"])
}

@Test func termThatDoesNotFitIsSkippedForALaterOne() {
    let selected = TermPrompt.select(
        ["GitLab", "Homebrewing", "Homeserver"], focus: ["Homebrew"], budget: 10, tokens: perCharacter)
    #expect(selected == ["Homeserver"])
}

@Test func termLongerThanTheBudgetIsNeverTaken() {
    #expect(TermPrompt.select(["Homebrewing"], focus: ["Homebrew"], budget: 10, tokens: perCharacter).isEmpty)
}

@Test func emptyFocusFallsBackToListOrder() {
    let selected = TermPrompt.select(["GitLab", "Homebrew", "Proxmox"], focus: [], budget: 20, tokens: perTerm)
    #expect(selected == ["GitLab", "Homebrew"])
}

@Test func similarityIgnoresCaseAndPunctuation() {
    #expect(TermPrompt.similarity("PHP-Stan", "phpstan") == 1)
    #expect(TermPrompt.similarity("Homebrew", "Homeroot") > TermPrompt.similarity("GitLab", "Homeroot"))
}
