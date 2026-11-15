import Foundation
import Testing
import ZackCore
import ZackWhisper

@testable import ZackDesktop

/// Empty files at the manifest's paths in the hub layout WhisperKit reads; no model, no network.
enum WhisperFakeModel {
    static func write(in base: URL) throws {
        let model = WhisperModelStore.modelFolder(in: base)
        let tokenizer = WhisperModelStore.tokenizerFolder(in: base)
        let files =
            WhisperModelManifest.model.map { model.appending(path: $0.path) }
            + WhisperModelManifest.tokenizer.map { tokenizer.appending(path: $0.path) }
        for url in files {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: url)
        }
    }

    static func exists(in base: URL) -> Bool {
        [WhisperModelStore.modelFolder(in: base), WhisperModelStore.tokenizerFolder(in: base)].contains {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}

struct WhisperSetupTests {
    let models = FileManager.default.temporaryDirectory.appending(path: "zack-whisper-\(UUID().uuidString)")

    /// The fake files carry no real model, so the verification is stubbed: it passes unless `verified` is false.
    func makeSetup(verified: Bool = true, downloadWrites: Bool = true) -> WhisperSetup {
        WhisperSetup(
            modelsDirectory: models,
            downloader: { base, progress in
                if downloadWrites { try WhisperFakeModel.write(in: base) }
                progress(1)
            },
            verifier: { _ in if !verified { throw ZackError.modelUnverified("config.json") } })
    }

    @Test func statusIsReadyOnlyWhenComplete() throws {
        defer { try? FileManager.default.removeItem(at: models) }
        let setup = makeSetup()
        #expect(setup.status() == .missing)
        try WhisperFakeModel.write(in: models)
        #expect(setup.status() == .ready)
        let tokenizer = WhisperModelStore.tokenizerFolder(in: models).appending(path: "tokenizer.json")
        try FileManager.default.removeItem(at: tokenizer)
        #expect(setup.status() == .missing)
    }

    @Test func downloadKeepsAVerifiedModel() async throws {
        defer { try? FileManager.default.removeItem(at: models) }
        try await makeSetup().download { _ in }
        #expect(makeSetup().status() == .ready)
    }

    @Test func downloadDeletesAnUnverifiedModel() async throws {
        defer { try? FileManager.default.removeItem(at: models) }
        // Parakeet shares the models directory and must survive.
        let parakeet = models.appending(path: "parakeet/config.json")
        try FileManager.default.createDirectory(
            at: parakeet.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: parakeet)
        let setup = makeSetup(verified: false)
        await #expect(throws: ZackError.modelUnverified("config.json")) { try await setup.download { _ in } }
        #expect(setup.status() == .missing)
        #expect(!WhisperFakeModel.exists(in: models))
        #expect(FileManager.default.fileExists(atPath: parakeet.path))
    }

    @Test func verifyDeletesAChangedCopy() async throws {
        defer { try? FileManager.default.removeItem(at: models) }
        try WhisperFakeModel.write(in: models)
        await #expect(throws: ZackError.modelUnverified("config.json")) {
            try await makeSetup(verified: false).verify()
        }
        #expect(!WhisperFakeModel.exists(in: models))
    }

    @Test func verifyKeepsAMatchingCopy() async throws {
        defer { try? FileManager.default.removeItem(at: models) }
        try WhisperFakeModel.write(in: models)
        try await makeSetup().verify()
        #expect(makeSetup().status() == .ready)
    }

    @Test(.germanUI) func downloadSizeIsTheManifestRounded() {
        let bytes = (WhisperModelManifest.model + WhisperModelManifest.tokenizer).reduce(0) { $0 + $1.size }
        #expect(Int((Double(bytes) / 10_000_000).rounded()) * 10 == 650)
        #expect(WhisperSetup.downloadSize == "etwa 650 MB")
    }
}
