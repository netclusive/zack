import Foundation
import Testing
import ZackTestSupport

@testable import ZackCore

private let second = AudioClip(samples: Array(repeating: 0, count: 16_000))
private let homeroot = "Über Homeroot ziehe ich gitleaks."
private let homebrew = "Über Homebrew ziehe ich gitleaks."

/// Words of `text` split at spaces, confidence 0.99 unless `low` names the word.
private func recognition(_ text: String, low: [String: Float] = [:]) -> Recognition {
    let words = text.split(separator: " ").map { word in
        let bare = word.trimmingCharacters(in: .punctuationCharacters)
        return RecognizedWord(text: String(word), confidence: low[bare] ?? 0.99)
    }
    return Recognition(text: text, words: words)
}

private func processor(
    _ secondOpinion: RecordingSecondOpinion?, vocabulary: String = "Homebrew\ngitleaks",
    checkTimeout: Duration = TermCheck.timeout
) -> TextProcessor {
    TextProcessor(
        vocabulary: VocabularyFile.parse(vocabulary), snippets: [Snippet(name: "Gruß", text: "Viele Grüße")],
        secondOpinion: secondOpinion, checkTimeout: checkTimeout)
}

@Test func checkReplacesOnlyTheMarkedWord() async {
    let opinion = RecordingSecondOpinion(.answer(homebrew))
    let result = await processor(opinion).process(
        recognition(homeroot, low: ["Homeroot": 0.35]), audio: second, context: RuleContext())
    #expect(result.body == homebrew)
    #expect(result.final == homebrew)
    #expect(result.usedCheck)
    #expect(result.checked)
    #expect(result.markedWords == 1)
    #expect(result.checkDuration != nil)
}

@Test func ruledFinalStaysTheUncheckedText() async {
    let opinion = RecordingSecondOpinion(.answer(homebrew))
    let result = await processor(opinion).process(
        recognition(homeroot, low: ["Homeroot": 0.35]), audio: second, context: RuleContext())
    #expect(result.ruledFinal == homeroot)
    #expect(result.ruled == homeroot)
}

@Test func otherTextGoesThroughTheRules() async {
    let opinion = RecordingSecondOpinion(.answer("Über home brew ziehe ich gitleaks."))
    let result = await processor(opinion, vocabulary: "home brew => Homebrew\ngitleaks").process(
        recognition(homeroot, low: ["Homeroot": 0.35]), audio: second, context: RuleContext())
    #expect(result.body == homebrew)
}

/// The time rule changes the words around the marked one; the splice must still replace only that word.
@Test(arguments: ["Um 16.45 Uhr ziehe ich Homebrew.", "Um 16:45 Uhr ziehe ich Homebrew."])
func checkReplacesTheMarkedWordNextToAFormattedTime(answer: String) async {
    let opinion = RecordingSecondOpinion(.answer(answer))
    let result = await processor(opinion).process(
        recognition("Um 16.45 Uhr ziehe ich Homeroot.", low: ["Homeroot": 0.35]), audio: second,
        context: RuleContext())
    #expect(result.ruled == "Um 16:45 Uhr ziehe ich Homeroot.")
    #expect(result.body == "Um 16:45 Uhr ziehe ich Homebrew.")
    #expect(result.usedCheck)
}

@Test func focusCarriesTheMarkedRanges() async {
    let opinion = RecordingSecondOpinion(.answer("Den Bericht von PHPStan schicke ich."))
    let result = await processor(opinion, vocabulary: "PHPStan").process(
        recognition("Den Bericht von Pierre Pistane schicke ich.", low: ["Pierre": 0.62, "Pistane": 0.60]),
        audio: second, context: RuleContext())
    let calls = await opinion.calls
    #expect(calls.map(\.focus) == [["PierrePistane"]])
    #expect(calls.map(\.terms) == [["PHPStan"]])
    #expect(calls.map(\.samples) == [16_000])
    #expect(result.body == "Den Bericht von PHPStan schicke ich.")
}

@Test func languageReachesTheSecondOpinion() async {
    let opinion = RecordingSecondOpinion(.answer("I use Homebrew daily."))
    let result = await processor(opinion).process(
        recognition("I use Homeroot daily.", low: ["Homeroot": 0.3]), audio: second,
        context: RuleContext(language: .english))
    #expect(await opinion.calls.map(\.language) == [.english])
    #expect(result.body == "I use Homebrew daily.")
}

@Test func noCheckWithoutMarkedWords() async {
    let opinion = RecordingSecondOpinion(.answer(homebrew))
    let result = await processor(opinion).process(
        recognition(homeroot, low: ["Homeroot": 0.626]), audio: second, context: RuleContext())
    #expect(await opinion.calls.isEmpty)
    #expect(!result.checked)
    #expect(result.body == homeroot)
}

enum NoCheckCase: String, CaseIterable, CustomTestStringConvertible {
    case signalWord, codeMode, snippet, emptyVocabulary, noAudio, longAudio

    var testDescription: String { rawValue }

    var raw: String {
        switch self {
        case .signalWord: "Über Homeroot, nein, über Homeroot ziehe ich gitleaks."
        case .snippet: "Baustein Gruß."
        default: homeroot
        }
    }

    var vocabulary: String { self == .emptyVocabulary ? "" : "Homebrew\ngitleaks" }
    var context: RuleContext { RuleContext(mode: self == .codeMode ? .code : .prose) }

    var audio: AudioClip? {
        switch self {
        case .noAudio: nil
        case .longAudio: AudioClip(samples: Array(repeating: 0, count: 16_000 * 31))
        default: second
        }
    }
}

@Test(arguments: NoCheckCase.allCases)
func noCheckWhere(_ noCheck: NoCheckCase) async {
    let opinion = RecordingSecondOpinion(.answer(homebrew))
    let recognized = recognition(noCheck.raw, low: ["Homeroot": 0.3, "Gruß": 0.3])
    let checking = processor(opinion, vocabulary: noCheck.vocabulary)
    let result = await checking.process(recognized, audio: noCheck.audio, context: noCheck.context)
    let plain = await processor(nil, vocabulary: noCheck.vocabulary).process(noCheck.raw, context: noCheck.context)
    #expect(await opinion.calls.isEmpty)
    #expect(!result.checked)
    #expect(result.body == plain.body)
    #expect(!checking.needsCheck(recognized, audio: noCheck.audio, context: noCheck.context))
}

@Test func timeoutKeepsTheRuleText() async {
    let opinion = RecordingSecondOpinion(.hang)
    let start = ContinuousClock.now
    let result = await processor(opinion, checkTimeout: .milliseconds(50)).process(
        recognition(homeroot, low: ["Homeroot": 0.35]), audio: second, context: RuleContext())
    #expect(ContinuousClock.now - start < .milliseconds(500))
    #expect(result.body == homeroot)
    #expect(result.checked)
    #expect(!result.usedCheck)
}

@Test func errorKeepsTheRuleText() async {
    let opinion = RecordingSecondOpinion(.fail)
    let result = await processor(opinion).process(
        recognition(homeroot, low: ["Homeroot": 0.35]), audio: second, context: RuleContext())
    #expect(result.body == homeroot)
    #expect(result.checked)
    #expect(!result.usedCheck)
}

@Test func cancellationKeepsTheRuleText() async {
    let opinion = RecordingSecondOpinion(.held(homebrew))
    let checking = processor(opinion, checkTimeout: .seconds(5))
    let task = Task {
        await checking.process(recognition(homeroot, low: ["Homeroot": 0.35]), audio: second, context: RuleContext())
    }
    await opinion.waitForCall()
    let start = ContinuousClock.now
    task.cancel()
    let result = await task.value
    #expect(ContinuousClock.now - start < .milliseconds(500))
    #expect(result.body == homeroot)
    #expect(!result.usedCheck)
    await opinion.release()
}

@Test func needsCheckAgreesWithProcess() async {
    let opinion = RecordingSecondOpinion(.answer(homebrew))
    let checking = processor(opinion)
    for low: Float in [0.35, 0.9] {
        let recognized = recognition(homeroot, low: ["Homeroot": low])
        let expected = checking.needsCheck(recognized, audio: second, context: RuleContext())
        let result = await checking.process(recognized, audio: second, context: RuleContext())
        #expect(expected == result.checked)
        #expect(expected == (low < TermCheck.threshold))
    }
}

@Test func withoutSecondOpinionNoCheckIsNeeded() {
    let recognized = recognition(homeroot, low: ["Homeroot": 0.35])
    #expect(!processor(nil).needsCheck(recognized, audio: second, context: RuleContext()))
}
