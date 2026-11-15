import FluidAudio
import Foundation
import Testing
import ZackCore

@testable import ZackParakeet

/// The Parakeet manifest and its store; the checksum itself is tested in ZackCoreTests/ModelManifestTests.
struct ParakeetModelManifestTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "zack-manifest-\(UUID().uuidString)")

    /// Every file FluidAudio checks lies in the manifest, so nothing loads unverified.
    @Test func manifestCoversEveryRequiredPath() {
        let paths = ParakeetModelManifest.ultra.map(\.path)
        for required in ParakeetModelStore.requiredPaths(.ultra) {
            #expect(paths.contains(required) || paths.contains { $0.hasPrefix(required + "/") }, "\(required)")
        }
    }

    @Test func manifestEntriesAreWellFormed() {
        let files = ParakeetModelManifest.ultra
        #expect(files.count == 20)
        #expect(Set(files.map(\.path)).count == files.count)
        let hex = Set("0123456789abcdef")
        for file in files {
            #expect(file.sha256.count == 64 && file.sha256.allSatisfy(hex.contains), "\(file.path)")
            #expect(file.size >= 0 && !file.path.hasPrefix("/") && !file.path.contains(".."), "\(file.path)")
        }
    }

    @Test func downloadPinsTheMeasuredCommit() {
        ParakeetModelStore.pinRevision(.ultra)
        #expect(
            ModelRegistry.revisionOverrides[Repo.parakeetUltra.remotePath] == ParakeetModelManifest.ultraRevision)
    }

    /// v3 is bench only and has no manifest: verifying it fails closed.
    @Test func variantWithoutManifestFails() {
        #expect(throws: ZackError.modelUnverified("parakeet-v3")) {
            try ParakeetModelStore.verify(.v3, in: folder)
        }
    }
}
