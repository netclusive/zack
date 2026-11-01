import Testing

@testable import ZackCore

@Test func vocabularyItemsMatchTheParser() {
    let text = "# Kopf\nVMware\ngit hub => GitHub\n  Kibana  \nabc =>\n=> x\n"
    let document = EntryDocument<VocabularyFormat>(text: text)
    #expect(
        document.items.map(\.entry) == [
            VocabularyEntry(spelling: "VMware"), VocabularyEntry(spelling: "GitHub", heardAs: "git hub"),
            VocabularyEntry(spelling: "Kibana"),
        ])
    #expect(document.items.map(\.line) == [1, 2, 3])
    #expect(document.unreadableCount == 2)
    let parsed = VocabularyFile.parse(text)
    #expect(parsed.terms == ["VMware", "GitHub", "Kibana"])
    #expect(parsed.replacements == [.init(from: "git hub", to: "GitHub")])
}

@Test func snippetItemsMatchTheParser() {
    let text = "Gruß => Viele Grüße\\nMax Mustermann\nohne Pfeil\nLeer =>\n"
    let document = EntryDocument<SnippetFormat>(text: text)
    #expect(document.items.map(\.entry) == SnippetFile.parse(text))
    #expect(document.items.map(\.entry) == [Snippet(name: "Gruß", text: "Viele Grüße\nMax Mustermann")])
    #expect(document.unreadableCount == 2)
}

@Test func snippetLineEscapesEveryLineBreak() {
    #expect(
        SnippetFormat.line(for: Snippet(name: " Gruß ", text: "Viele Grüße\r\nMax\nMustermann"))
            == "Gruß => Viele Grüße\\nMax\\nMustermann")
}

@Test func editingKeepsCommentsAndOtherLines() {
    var document = EntryDocument<VocabularyFormat>(text: "# Kopf\r\ngit hub=>GitHub\r\nVMware\r\n")
    document.replace(line: 2, with: VocabularyEntry(spelling: "VMware", heardAs: "vm ware"))
    document.append(VocabularyEntry(spelling: "Kibana"))
    #expect(document.text == "# Kopf\r\ngit hub=>GitHub\r\nvm ware => VMware\r\nKibana\r\n")
    document.remove(line: 1)
    #expect(document.text == "# Kopf\r\nvm ware => VMware\r\nKibana\r\n")
}

@Test func issuesFlagEveryRule() {
    #expect(
        VocabularyFormat.issues(in: VocabularyEntry(spelling: "  ")) == [EntryIssue(field: .spelling, problem: .empty)])
    #expect(
        VocabularyFormat.issues(in: VocabularyEntry(spelling: "a => b")) == [
            EntryIssue(field: .spelling, problem: .arrow)
        ])
    #expect(
        VocabularyFormat.issues(in: VocabularyEntry(spelling: "#hashtag")) == [
            EntryIssue(field: .spelling, problem: .leadingHash)
        ])
    #expect(VocabularyFormat.issues(in: VocabularyEntry(spelling: "#C", heardAs: "c sharp")).isEmpty)
    #expect(
        VocabularyFormat.issues(in: VocabularyEntry(spelling: "C", heardAs: "#c")) == [
            EntryIssue(field: .heardAs, problem: .leadingHash)
        ])
    #expect(
        VocabularyFormat.issues(in: VocabularyEntry(spelling: "Max\nMustermann")) == [
            EntryIssue(field: .spelling, problem: .lineBreak)
        ])
    #expect(
        SnippetFormat.issues(in: Snippet(name: "Gruß\nMax", text: "Hallo")) == [
            EntryIssue(field: .name, problem: .lineBreak)
        ])
    #expect(
        SnippetFormat.issues(in: Snippet(name: "A => B", text: "Hallo")) == [EntryIssue(field: .name, problem: .arrow)])
    #expect(SnippetFormat.issues(in: Snippet(name: "Gruß", text: " ")) == [EntryIssue(field: .text, problem: .empty)])
    #expect(SnippetFormat.issues(in: Snippet(name: "Pfeil", text: "a => b")).isEmpty)
}

@Test func laterSnippetWithTheSameSpokenNameIsADuplicate() {
    let document = EntryDocument<SnippetFormat>(text: "Grüße => A\nGruesse => B\nGruß => C\n")
    #expect(document.laterDuplicates == [1])
}

@Test func laterDuplicateSpellingIsMarked() {
    #expect(EntryDocument<VocabularyFormat>(text: "VMware\nvm ware => VMware\n").laterDuplicates == [1])
}

@Test func searchIgnoresCase() {
    let document = EntryDocument<SnippetFormat>(text: "Gruß => Viele Grüße\nAdresse => example.com\n")
    #expect(document.items(matching: "VIELE").map(\.line) == [0])
    #expect(document.items(matching: "Example").map(\.line) == [1])
    #expect(document.items(matching: "").count == 2)
}
