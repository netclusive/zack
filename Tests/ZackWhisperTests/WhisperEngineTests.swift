import Foundation
import Testing
import ZackCore
import ZackTestSupport

@testable import ZackWhisper

@Test func promptTokensDropSpecialTokens() {
    let tokens = WhisperEngine.promptTokens(
        terms: ["Homebrew"], focus: [], encode: { _ in [5, 50257, 7] }, specialBegin: 50257)
    #expect(tokens == [5, 7])
}

@Test func promptTokensStayWithinTheBudget() {
    let terms = (1...40).map { "Begriff\($0)" }
    let tokens = WhisperEngine.promptTokens(
        terms: terms, focus: ["Begriff7"], encode: { $0.unicodeScalars.map { Int($0.value) } }, specialBegin: 50257)
    #expect(!tokens.isEmpty)
    #expect(tokens.count <= TermPrompt.tokenBudget)
}

@Test func promptTokensWithoutTermsAreEmpty() {
    let tokens = WhisperEngine.promptTokens(terms: [], focus: ["x"], encode: { _ in [1] }, specialBegin: 50257)
    #expect(tokens.isEmpty)
}

@Test func prepareWithoutModelThrowsModelMissing() async {
    let base = FileManager.default.temporaryDirectory.appending(path: "zack-whisper-\(UUID().uuidString)")
    let engine = WhisperEngine(base: base)
    await #expect(throws: ZackError.modelMissing("whisper-terms")) { try await engine.prepare() }
}

/// WhisperKit fetches the tokenizer from the hub when the local load fails; a changed tokenizer must stop the load.
@Test func prepareRefusesAChangedTokenizer() async throws {
    let base = FileManager.default.temporaryDirectory.appending(path: "zack-whisper-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: base) }
    let files =
        WhisperModelManifest.model.map { WhisperModelStore.modelFolder(in: base).appending(path: $0.path) }
        + WhisperModelManifest.tokenizer.map { WhisperModelStore.tokenizerFolder(in: base).appending(path: $0.path) }
    for url in files {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("fake".utf8).write(to: url)
    }
    let engine = WhisperEngine(base: base)
    await #expect(throws: ZackError.modelUnverified(WhisperModelManifest.tokenizer[0].path)) {
        try await engine.prepare()
    }
}

@Test func recognizeBeforePrepareThrows() async {
    let engine = WhisperEngine(base: FileManager.default.temporaryDirectory)
    let clip = AudioClip(samples: (0..<16_000).map { Float(sin(Double($0) / 8)) * 0.2 })
    await #expect(throws: ZackError.engineUnavailable("whisper-terms")) {
        try await engine.recognize(clip, terms: [], focus: [], language: .german)
    }
}

/// Needs the installed model (`~/Library/Application Support/Zack/Models`) and `ZACK_INTEGRATION=1`.
@Suite(.enabled(if: Fixture.integration), .serialized)
struct WhisperEngineHardwareTests {
    @Test func recognizesTheFixtureSentence() async throws {
        let engine = WhisperEngine(base: try ModelStorage.directory(createIfNeeded: false))
        try await engine.prepare()
        try await engine.warmUp()
        let text = try await engine.recognize(
            try Fixture.hallo(), terms: ["Homebrew", "GitLab"], focus: [], language: .german)
        #expect(text.contains("Spracherkennung"), "\(text)")
        #expect(await engine.lastPromptTokenCount > 0)
    }
}
