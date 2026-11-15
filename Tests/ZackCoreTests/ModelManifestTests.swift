import Foundation
import Testing

@testable import ZackCore

/// Checks the file verification on temporary folders; no model and no network needed.
struct ModelManifestTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "zack-manifest-\(UUID().uuidString)")

    /// SHA-256 of "abc" (FIPS 180-2 test vector).
    static let abc = ModelManifest.File(
        path: "Encoder.mlmodelc/weights/weight.bin", size: 3,
        sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    /// SHA-256 of the empty string.
    static let empty = ModelManifest.File(
        path: "config.json", size: 0, sha256: "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")

    func write(_ text: String, to path: String) throws {
        let url = folder.appending(path: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    @Test func matchingFilesPass() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("abc", to: Self.abc.path)
        try write("", to: Self.empty.path)
        try ModelManifest.verify([Self.abc, Self.empty], in: folder)
    }

    @Test func changedContentFails() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("abd", to: Self.abc.path)
        #expect(throws: ZackError.modelUnverified(Self.abc.path)) {
            try ModelManifest.verify([Self.abc], in: folder)
        }
    }

    @Test func missingFileFails() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("abc", to: Self.abc.path)
        #expect(throws: ZackError.modelUnverified(Self.empty.path)) {
            try ModelManifest.verify([Self.abc, Self.empty], in: folder)
        }
    }

    @Test func otherSizeFails() throws {
        defer { try? FileManager.default.removeItem(at: folder) }
        try write("abcd", to: Self.abc.path)
        #expect(throws: ZackError.modelUnverified(Self.abc.path)) {
            try ModelManifest.verify([Self.abc], in: folder)
        }
    }
}
