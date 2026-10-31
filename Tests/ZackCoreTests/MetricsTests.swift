import Testing

@testable import ZackCore

@Test func werIsZeroForIdenticalText() {
    #expect(Metrics.wordErrorRate(reference: "Das ist ein Test.", hypothesis: "das ist ein test") == 0)
}

@Test func werCountsSubstitution() {
    #expect(Metrics.wordErrorRate(reference: "das ist ein test", hypothesis: "das ist kein test") == 0.25)
}

@Test func werIgnoresFillers() {
    #expect(Metrics.wordErrorRate(reference: "Äh, das läuft.", hypothesis: "Das läuft.") == 0)
}

@Test func werCountsInsertionAndDeletion() {
    #expect(Metrics.wordErrorRate(reference: "a b c d", hypothesis: "a c d e") == 0.5)
}

@Test func termHitRateIsCaseSensitive() {
    let rate = Metrics.termHitRate(
        terms: ["GitHub", "VMware", "SharePoint"], in: "Im GitHub und im vmware, SharePoint fehlt nicht.")
    #expect(abs((rate ?? -1) - 2.0 / 3.0) < 0.0001)
}

@Test func termHitRateWithoutTermsIsNil() {
    #expect(Metrics.termHitRate(terms: [], in: "egal") == nil)
}

@Test func matchesIgnoresCaseAndPunctuation() {
    #expect(Metrics.matches(expected: "Das Treffen ist am Mittwoch.", actual: "das Treffen ist am Mittwoch"))
    #expect(!Metrics.matches(expected: "Das Treffen ist am Mittwoch.", actual: "Das Treffen ist am Dienstag."))
}

@Test func matchesIgnoresCompoundSpelling() {
    let expected = "Schick das bitte an das Supportteam."
    #expect(Metrics.matches(expected: expected, actual: "Schick das bitte an das Support-Team."))
    #expect(Metrics.matches(expected: expected, actual: "Schick das bitte an das Support Team."))
    #expect(Metrics.matches(expected: "VMware-Cluster läuft.", actual: "VMware Cluster läuft"))
    #expect(!Metrics.matches(expected: expected, actual: "Schick das bitte an das Sales-Team."))
}

/// Whisper writes "Kibana-Dashboard" for "Kibana Dashboard"; spelling of compounds is not a recognition error.
@Test(arguments: [
    ("Ich schaue mir das im Kibana Dashboard an.", "Ich schaue mir das im Kibana-Dashboard an."),
    ("Der Pull Request ist approved.", "Der Pull-Request ist approved."),
    ("an das Supportteam", "an das Support-Team"),
    ("an das Supportteam", "an das Support Team"),
    ("Baustein Rückruf", "Bausteinrückruf"),
    ("Das Ticket hängt im Node-RED Flow.", "Das Ticket hängt im Node-RED-Flow."),
    ("ein Pull Request Review", "ein PullRequestReview"),
])
func werIgnoresCompoundSpelling(reference: String, hypothesis: String) {
    #expect(Metrics.wordErrorRate(reference: reference, hypothesis: hypothesis) == 0)
    #expect(Metrics.wordErrorRate(reference: hypothesis, hypothesis: reference) == 0)
}

@Test func werStillCountsSubstitutionNextToCompound() {
    #expect(
        Metrics.wordErrorRate(reference: "das Kibana Dashboard läuft", hypothesis: "das Kibana-Dashboard steht")
            == 0.25)
}

@Test(arguments: ["das Kibana-Dashboard steht", "das Kibana Dashboard steht", "das Kibanadashboard steht"])
func werDenominatorDoesNotDependOnHypothesisSpelling(hypothesis: String) {
    #expect(Metrics.wordErrorRate(reference: "das Kibana Dashboard läuft", hypothesis: hypothesis) == 0.25)
}

@Test func matchesIgnoresHyphenatedOpenCompound() {
    #expect(Metrics.matches(expected: "Der Pull Request ist approved.", actual: "Der Pull-Request ist approved."))
    #expect(Metrics.matches(expected: "Schick es an das Supportteam.", actual: "Schick es an das Support-Team."))
}

/// Joining whole texts would equate these; only real compounds may merge.
@Test func wordBoundariesAcrossDifferentWordsStillCount() {
    let expected = "Wir brauchen neue Router."
    let actual = "Wir brauchen neuer Outer."
    #expect(!Metrics.matches(expected: expected, actual: actual))
    #expect(Metrics.wordErrorRate(reference: expected, hypothesis: actual) > 0)
}

@Test func percentileUsesNearestRank() {
    #expect(Metrics.percentile([5, 1, 4, 2, 3], 50) == 3)
    #expect(Metrics.percentile([5, 1, 4, 2, 3], 95) == 5)
    #expect(Metrics.percentile([], 95) == 0)
    #expect(Metrics.percentile([1, 2, 3, 4], 50) == 2)
    #expect(Metrics.percentile([41, 61], 95) == 61)
    #expect(Metrics.percentile([51, 71], 95) == 71)
}
