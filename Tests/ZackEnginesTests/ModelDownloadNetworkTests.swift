import Foundation
import Testing
import ZackCore

@testable import ZackParakeet

/// The real download from Hugging Face, about 630 MB; needs `ZACK_NETWORK=1`. Writes to a temporary folder only, so
/// an installed model stays as it is. Run it after a FluidAudio update or a new pin.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ZACK_NETWORK"] == "1"))
struct ModelDownloadNetworkTests {
    @Test(.timeLimit(.minutes(30))) func pinnedDownloadPassesTheManifest() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "zack-download-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        try await ParakeetModelStore.download(.ultra, to: base) { _ in }
        #expect(throws: Never.self) { try ParakeetModelStore.verify(.ultra, in: base) }
    }
}
