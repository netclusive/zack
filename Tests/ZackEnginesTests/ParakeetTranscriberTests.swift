import Foundation
import Testing
import ZackCore
import ZackTestSupport

@testable import ZackParakeet

@Suite(.enabled(if: Fixture.integration), .serialized)
struct ParakeetTranscriberTests {
    @Test(arguments: [ParakeetTranscriber.Variant.v3, .ultra])
    func transcribesGermanFixture(variant: ParakeetTranscriber.Variant) async throws {
        let engine = ParakeetTranscriber(variant: variant)
        try await engine.prepare()
        let text = try await engine.transcribe(try Fixture.hallo(), hints: [])
        #expect(text.localizedCaseInsensitiveContains("Test"), "\(variant): \(text)")
    }

    @Test func concurrentPrepareLoadsModelsOnce() async throws {
        let engine = ParakeetTranscriber(variant: .v3)
        async let first: Void = engine.prepare()
        async let second: Void = engine.prepare()
        _ = try await (first, second)
        let text = try await engine.transcribe(try Fixture.hallo(), hints: [])
        #expect(text.localizedCaseInsensitiveContains("Test"), "\(text)")
        #expect(await engine.loadCount == 1)
    }
}

/// The app path: without models on disk, loading fails at once instead of downloading. Needs no model.
@Test func localOnlyWithoutModelsNeverDownloads() async throws {
    let empty = FileManager.default.temporaryDirectory.appending(path: "zack-empty-\(UUID().uuidString)")
    let engine = ParakeetTranscriber(variant: .ultra, modelsDirectory: empty, policy: .localOnly)
    await #expect(throws: ZackError.modelMissing("parakeet-ultra")) { try await engine.prepare() }
}

/// Where the bench loads from: an existing complete copy is never routed through a path that can purge it.
struct ParakeetSourceTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "zack-source-\(UUID().uuidString)")
    var base: URL { root.appending(path: "Zack/Models") }
    var legacy: URL { root.appending(path: "FluidAudio/Models") }

    func makeModel(in directory: URL, complete: Bool = true) throws {
        let folder = ParakeetModelStore.modelFolder(.ultra, in: directory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, path) in ParakeetModelStore.requiredPaths(.ultra).enumerated() where complete || index > 0 {
            let url = folder.appending(path: path)
            if path.hasSuffix(".mlmodelc") {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } else {
                try Data("{}".utf8).write(to: url)
            }
        }
    }

    func source() -> ParakeetTranscriber.Source {
        ParakeetTranscriber.source(for: .ultra, base: base, legacy: legacy)
    }

    @Test func completeBaseIsLoadedLocally() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: base)
        try makeModel(in: legacy)
        #expect(source() == .local(base))
    }

    @Test func onlyLegacyCompleteIsLoadedLocally() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: legacy)
        #expect(source() == .local(legacy))
    }

    @Test func incompleteBaseWithCompleteLegacyUsesLegacy() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: base, complete: false)
        try makeModel(in: legacy)
        #expect(source() == .local(legacy))
    }

    @Test func noCompleteCopyDownloadsIntoBase() throws {
        defer { try? FileManager.default.removeItem(at: root) }
        try makeModel(in: legacy, complete: false)
        #expect(source() == .download(base))
    }
}

/// FluidAudio's long-audio path (chunks over 15 s) with a clip near the 3-minute limit. Uses the app's copy in
/// `Zack/Models` with `localOnly`, so it never downloads.
@Test(.enabled(if: Fixture.integration)) func longClipNearThreeMinutes() async throws {
    let models = try ModelStorage.directory(createIfNeeded: false)
    try #require(ParakeetModelStore.isComplete(.ultra, in: models), "Parakeet Ultra fehlt in \(models.path)")
    let hallo = try Fixture.hallo()
    let pause = [Float](repeating: 0, count: 8_800)
    let clip = AudioClip(samples: Array(repeating: hallo.samples + pause, count: 44).flatMap { $0 })
    #expect(clip.duration > 170 && clip.duration < 180)
    let engine = ParakeetTranscriber(variant: .ultra, policy: .localOnly)
    try await engine.prepare()
    let start = ContinuousClock.now
    let text = try await engine.transcribe(clip, hints: [])
    let elapsed = start.duration(to: .now)
    let count = TextTools.words(text).filter { $0 == "test" }.count
    #expect(count >= 40, "\(count) of 44, \(elapsed)")
    print("long clip: \(clip.duration) s audio, \(elapsed) recognition, \(count) of 44")
}
