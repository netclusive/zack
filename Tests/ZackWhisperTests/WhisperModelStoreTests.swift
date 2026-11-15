import Foundation
import Testing
import ZackCore

@testable import ZackWhisper

/// Store checks on temporary folders with fake files; no model and no network needed.
struct WhisperModelStoreTests {
    let base = FileManager.default.temporaryDirectory.appending(path: "zack-whisper-\(UUID().uuidString)")

    /// Writes a placeholder for every manifest file, skipping `missing` (a model path).
    func writeFakeModel(missing: String? = nil) throws {
        let model = WhisperModelManifest.model.filter { $0.path != missing }.map {
            WhisperModelStore.modelFolder(in: base).appending(path: $0.path)
        }
        let tokenizer = WhisperModelManifest.tokenizer.map {
            WhisperModelStore.tokenizerFolder(in: base).appending(path: $0.path)
        }
        for url in model + tokenizer {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("fake".utf8).write(to: url)
        }
    }

    @Test func foldersFollowTheHubLayout() {
        let model = WhisperModelStore.modelFolder(in: base).path
        let variant = "openai_whisper-large-v3-v20240930_turbo_632MB"
        #expect(model == base.path + "/models/argmaxinc/whisperkit-coreml/" + variant)
        #expect(WhisperModelStore.tokenizerFolder(in: base).path == base.path + "/models/openai/whisper-large-v3")
    }

    @Test func incompleteFolderIsNotComplete() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try writeFakeModel(missing: "TextDecoder.mlmodelc/weights/weight.bin")
        #expect(!WhisperModelStore.isComplete(in: base))
    }

    @Test func completeFolderIsComplete() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try writeFakeModel()
        #expect(WhisperModelStore.isComplete(in: base))
    }

    @Test func emptyFolderIsNotComplete() {
        #expect(!WhisperModelStore.isComplete(in: base))
    }

    @Test func verifyNamesTheFirstDifferingFile() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try writeFakeModel()
        #expect(throws: ZackError.modelUnverified(WhisperModelManifest.model[0].path)) {
            try WhisperModelStore.verify(in: base)
        }
    }

    @Test func removeDeletesModelAndTokenizer() throws {
        defer { try? FileManager.default.removeItem(at: base) }
        try writeFakeModel()
        let other = base.appending(path: "parakeet-tdt-0.6b-v3-coreml/config.json")
        try FileManager.default.createDirectory(
            at: other.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: other)
        try WhisperModelStore.remove(from: base)
        #expect(!FileManager.default.fileExists(atPath: WhisperModelStore.modelFolder(in: base).path))
        #expect(!FileManager.default.fileExists(atPath: WhisperModelStore.tokenizerFolder(in: base).path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func removeWithoutModelDoesNothing() throws {
        try WhisperModelStore.remove(from: base)
    }

    @Test func manifestListsEveryFileOnce() {
        let hex = Set("0123456789abcdef")
        for files in [WhisperModelManifest.model, WhisperModelManifest.tokenizer] {
            #expect(Set(files.map(\.path)).count == files.count)
            for file in files {
                #expect(file.size > 0, "\(file.path)")
                #expect(file.sha256.count == 64 && file.sha256.allSatisfy(hex.contains), "\(file.path)")
                #expect(!file.path.hasPrefix("/") && !file.path.contains(".."), "\(file.path)")
            }
        }
        #expect(WhisperModelManifest.model.count == 22)
        let tokenizer = WhisperModelManifest.tokenizer.map(\.path)
        #expect(tokenizer == ["config.json", "tokenizer.json", "tokenizer_config.json"])
    }
}
