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

    func makeSetup(downloads: Counter = Counter()) -> ModelSetup {
        ModelSetup(modelsDirectory: models, legacyDirectory: legacy) { _, progress in
            downloads.increment()
            progress(1)
        }
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
