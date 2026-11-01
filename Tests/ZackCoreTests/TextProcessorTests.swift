import Testing

@testable import ZackCore

/// Stands in for an on-device language model.
struct StubCleaner: Cleaner {
    let id = "stub"
    let output: String
    var delay: Duration = .zero

    func clean(_ text: String, mode: TextMode, vocabulary: [String], language: DictationLanguage) async throws -> String
    {
        if delay > .zero { try await Task.sleep(for: delay) }
        return output
    }
}

@Test func withoutSignalWordCleanerIsSkipped() async {
    let processor = TextProcessor(cleaner: StubCleaner(output: "falsch"))
    let result = await processor.process("Äh, alles läuft.", context: RuleContext())
    #expect(result.final == "Alles läuft.")
    #expect(!result.usedCleaner)
}

@Test func plausibleCleanerOutputIsUsed() async {
    let processor = TextProcessor(cleaner: StubCleaner(output: "Das Treffen ist am Mittwoch."))
    let result = await processor.process("Das Treffen ist am Dienstag, nein, am Mittwoch.", context: RuleContext())
    #expect(result.final == "Das Treffen ist am Mittwoch.")
    #expect(result.usedCleaner)
    #expect(!result.cleanerRejected)
}

@Test func implausibleCleanerOutputFallsBackToRules() async {
    let processor = TextProcessor(cleaner: StubCleaner(output: "Gerne, ich habe den Termin eingetragen."))
    let result = await processor.process("Das Treffen ist am Dienstag, nein, am Mittwoch.", context: RuleContext())
    #expect(result.final == "Das Treffen ist am Dienstag, nein, am Mittwoch.")
    #expect(result.cleanerRejected)
}

@Test func slowCleanerTimesOut() async {
    let processor = TextProcessor(
        cleaner: StubCleaner(output: "Das Treffen ist am Mittwoch.", delay: .seconds(2)),
        cleanerTimeout: .milliseconds(50))
    let start = ContinuousClock.now
    let result = await processor.process("Das Treffen ist am Dienstag, nein, am Mittwoch.", context: RuleContext())
    #expect(ContinuousClock.now - start < .milliseconds(500))
    #expect(result.cleanerRejected)
    #expect(result.final == "Das Treffen ist am Dienstag, nein, am Mittwoch.")
}

@Test func snippetBypassesCleaner() async {
    let processor = TextProcessor(
        snippets: [Snippet(name: "Gruß", text: "Viele Grüße")], cleaner: StubCleaner(output: "falsch"))
    let result = await processor.process("Baustein Gruß, nein.", context: RuleContext())
    #expect(result.final == "Baustein Gruß, nein.")
    let exact = await processor.process("Baustein Gruß.", context: RuleContext())
    #expect(exact.final == "Viele Grüße")
    #expect(!exact.usedCleaner)
}

@Test func cursorJoinRunsAfterCleaner() async {
    let processor = TextProcessor(cleaner: StubCleaner(output: "Am Mittwoch."))
    let result = await processor.process(
        "Am Dienstag, nein, am Mittwoch.", context: RuleContext(textBeforeCursor: "Treffen,"))
    #expect(result.final == " am Mittwoch.")
}

@Test func callerCancellationReturnsFallbackPromptly() async {
    let processor = TextProcessor(
        cleaner: StubCleaner(output: "Das Treffen ist am Mittwoch.", delay: .seconds(5)),
        cleanerTimeout: .seconds(2))
    let start = ContinuousClock.now
    let task = Task {
        await processor.process("Das Treffen ist am Dienstag, nein, am Mittwoch.", context: RuleContext())
    }
    try? await Task.sleep(for: .milliseconds(100))
    task.cancel()
    let result = await task.value
    #expect(ContinuousClock.now - start < .seconds(1))
    #expect(result.cleanerRejected)
    #expect(result.final == "Das Treffen ist am Dienstag, nein, am Mittwoch.")
}

@Test func alreadyCancelledCallerFallsBackWithoutWaiting() async {
    let processor = TextProcessor(
        cleaner: StubCleaner(output: "Das Treffen ist am Mittwoch.", delay: .seconds(5)))
    let start = ContinuousClock.now
    let task = Task {
        while !Task.isCancelled { await Task.yield() }
        return await processor.process("Das Treffen ist am Dienstag, nein, am Mittwoch.", context: RuleContext())
    }
    task.cancel()
    let result = await task.value
    #expect(ContinuousClock.now - start < .seconds(1))
    #expect(result.cleanerRejected)
}

@Test func cleanerDroppingFinalPunctuationGetsItBack() async {
    let processor = TextProcessor(cleaner: StubCleaner(output: "Schick das an Support"))
    let result = await processor.process("Schick das an Vertrieb, ich meine an Support.", context: RuleContext())
    #expect(result.usedCleaner)
    #expect(result.final == "Schick das an Support.")
}

@Test func cleanerPunctuationIsKeptAsIs() async {
    let processor = TextProcessor(cleaner: StubCleaner(output: "Schick das an Support!"))
    let result = await processor.process("Schick das an Vertrieb, ich meine an Support?", context: RuleContext())
    #expect(result.final == "Schick das an Support!")
}

@Test func noTerminatorIsAddedWhenRulesHadNone() async {
    let processor = TextProcessor(cleaner: StubCleaner(output: "Schick das an Support"))
    let result = await processor.process("Schick das an Vertrieb, ich meine an Support", context: RuleContext())
    #expect(result.final == "Schick das an Support")
}

@Test func needsCleanerMatchesProcess() {
    let processor = TextProcessor(
        snippets: [Snippet(name: "Gruß", text: "Viele Grüße")], cleaner: StubCleaner(output: "egal"))
    #expect(processor.needsCleaner("Das Treffen ist am Dienstag, nein, am Mittwoch.", context: RuleContext()))
    #expect(!processor.needsCleaner("Alles läuft.", context: RuleContext()))
    #expect(!processor.needsCleaner("Baustein Gruß", context: RuleContext()))
    #expect(!TextProcessor().needsCleaner("Am Dienstag, nein, am Mittwoch.", context: RuleContext()))
}

@Test func bodyHasNoCursorJoin() async {
    let processor = TextProcessor()
    let result = await processor.process("Der Server läuft.", context: RuleContext(textBeforeCursor: "Ich glaube,"))
    #expect(result.final == " der Server läuft.")
    #expect(result.body == "Der Server läuft.")
}

@Test func bodyOfASnippetIsTheSnippet() async {
    let processor = TextProcessor(snippets: [Snippet(name: "Gruß", text: "Viele Grüße")])
    let result = await processor.process("Baustein Gruß.", context: RuleContext(textBeforeCursor: "Danke,"))
    #expect(result.body == "Viele Grüße")
}

@Test func bodyUsesTheAcceptedCleanerOutput() async {
    let processor = TextProcessor(cleaner: StubCleaner(output: "Am Mittwoch."))
    let result = await processor.process(
        "Am Dienstag, nein, am Mittwoch.", context: RuleContext(textBeforeCursor: "Treffen,"))
    #expect(result.body == "Am Mittwoch.")
    #expect(result.final == " am Mittwoch.")
}

@Test func ruledFinalCarriesTheCursorJoin() async {
    let processor = TextProcessor(cleaner: StubCleaner(output: "Das Treffen ist am Mittwoch."))
    let result = await processor.process(
        "Das Treffen ist am Dienstag, nein, am Mittwoch.", context: RuleContext(textBeforeCursor: "Ende."))
    #expect(result.final == " Das Treffen ist am Mittwoch.")
    #expect(result.ruledFinal == " Das Treffen ist am Dienstag, nein, am Mittwoch.")
}

@Test func ruledFinalWithoutCleanerIsFinal() async {
    let processor = TextProcessor()
    let result = await processor.process("Der Server läuft.", context: RuleContext(textBeforeCursor: "Ich glaube,"))
    #expect(result.ruledFinal == result.final)
}

@Test func englishCorrectionGoesThroughTheCleaner() async {
    let processor = TextProcessor(cleaner: StubCleaner(output: "Let's meet on Wednesday."))
    let result = await processor.process(
        "Let's meet on Tuesday, no, Wednesday.", context: RuleContext(language: .english))
    #expect(result.usedCleaner)
    #expect(result.final == "Let's meet on Wednesday.")
}

@Test(arguments: [
    "Let's meet on Tuesday, um, no, Wednesday.",
    "Send it to sales, um, I mean support.",
    "Call me in the morning, er, no, in the afternoon.",
    "The budget comes from marketing, um, wait, from sales.",
    "The error only occurs in Chrome, um, make that Safari.",
    "Let's meet on Tuesday, uh no, Wednesday.",
])
func englishCommaSurvivesFillerRemoval(text: String) async {
    let context = RuleContext(language: .english)
    let processor = TextProcessor(cleaner: StubCleaner(output: "Let's meet on Wednesday."))
    #expect(processor.needsCleaner(text, context: context))
    let result = await processor.process(text, context: context)
    #expect(result.usedCleaner || result.cleanerRejected)
}

@Test func englishFillerWithoutCommaDoesNotCountAsComma() async {
    let text = "There is no problem, um, with the server."
    let context = RuleContext(language: .english)
    let processor = TextProcessor(cleaner: StubCleaner(output: "egal"))
    #expect(!processor.needsCleaner(text, context: context))
    let result = await processor.process(text, context: context)
    #expect(!result.usedCleaner && !result.cleanerRejected)
}
