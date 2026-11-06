import Foundation
import Testing
import ZackCore
import ZackParakeet

@testable import ZackDesktop

/// Works on temporary folders with the file layout FluidAudio checks, so no model and no network is needed.
struct ModelSetupTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "zack-models-\(UUID().uuidString)")
    var models: URL { root.appending(path: "Zack/Models") }
    var legacy: URL { root.appending(path: "FluidAudio/Models") }

    func makeModel(in base: URL, without missing: String? = nil) throws {
        let folder = ParakeetModelStore.modelFolder(ModelSetup.variant, in: base)
        for path in ParakeetModelStore.requiredPaths(ModelSetup.variant) where path != missing {
            let url = folder.appending(path: path)
            if path.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try Data("{}".utf8).write(to: url)
            }
        }
    }

    /// The fake files carry no real model, so the verification is stubbed: it passes unless `verified` is false.
    func makeSetup(downloads: Counter = Counter(), verified: Bool = true, downloadWrites: Bool = false) -> ModelSetup {
        let models = models
        return ModelSetup(
            modelsDirectory: models, legacyDirectory: legacy,
            downloader: { _, progress in
                downloads.increment()
                if downloadWrites { try makeModel(in: models) }
                progress(1)
            },
            verifier: { _ in if !verified { throw ZackError.modelUnverified("config.json") } })
    }

    @Test func downloadKeepsAVerifiedModel() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try await makeSetup(downloadWrites: true).download { _ in }
        #expect(makeSetup().status() == .ready)
    }

    @Test func downloadDropsAModelThatFailsVerification() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let setup = makeSetup(verified: false, downloadWrites: true)
        await #expect(throws: ZackError.modelUnverified("config.json")) { try await setup.download { _ in } }
        #expect(makeSetup().status() == .missing)
        #expect(!FileManager.default.fileExists(atPath: ParakeetModelStore.modelFolder(.ultra, in: models).path))
    }

    @Test func adoptRefusesABenchCopyThatFailsVerification() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: legacy)
        #expect(throws: ZackError.modelUnverified("config.json")) { try makeSetup(verified: false).adopt() }
        #expect(makeSetup().status() == .adoptable)
    }

    @Test func missingWithoutAnyCopy() {
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(makeSetup().status() == .missing)
    }

    @Test func readyWithACompleteCopy() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: models)
        #expect(makeSetup().status() == .ready)
    }

    @Test func benchCopyCanBeAdopted() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: legacy)
        #expect(makeSetup().status() == .adoptable)
    }

    @Test(arguments: ParakeetModelStore.requiredPaths(.ultra))
    func incompleteCopyIsMissing(missing: String) throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: models, without: missing)
        #expect(makeSetup().status() == .missing)
    }

    @Test func adoptMovesTheBenchCopy() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: legacy)
        try makeSetup().adopt()
        #expect(makeSetup().status() == .ready)
        let old = ParakeetModelStore.modelFolder(ModelSetup.variant, in: legacy)
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func adoptReplacesAnIncompleteDownload() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: models, without: ParakeetModelStore.requiredPaths(.ultra).first)
        try makeModel(in: legacy)
        try makeSetup().adopt()
        #expect(makeSetup().status() == .ready)
    }

    @Test func adoptRefusesAnIncompleteBenchCopyAndKeepsTheTarget() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: models)
        try makeModel(in: legacy, without: ParakeetModelStore.requiredPaths(.ultra).first)
        try makeSetup().adopt()
        #expect(makeSetup().status() == .ready)
        try FileManager.default.removeItem(at: models)
        #expect(throws: ZackError.modelMissing("parakeet-ultra")) { try makeSetup().adopt() }
    }

    @Test func onlyAnExplicitCallDownloads() async throws {
        defer { try? FileManager.default.removeItem(at: root) }
        let downloads = Counter()
        let setup = makeSetup(downloads: downloads)
        _ = setup.status()
        try makeModel(in: legacy)
        try setup.adopt()
        _ = setup.status()
        #expect(downloads.value == 0)
        try await setup.download { _ in }
        #expect(downloads.value == 1)
    }
}
