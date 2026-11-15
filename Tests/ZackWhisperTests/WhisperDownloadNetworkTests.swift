import Foundation
import Testing
import ZackCore

@testable import ZackWhisper

/// The real download from Hugging Face, about 650 MB; needs `ZACK_NETWORK=1`. Writes to a temporary folder only, so
/// an installed model stays as it is. Run it after a WhisperKit update or a new pin.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["ZACK_NETWORK"] == "1"))
struct WhisperDownloadNetworkTests {
    @Test(.timeLimit(.minutes(30))) func downloadVerifiesAndLoadsWithoutTheHub() async throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "zack-whisper-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: base) }
        try await WhisperModelStore.download(to: base) { _ in }
        #expect(throws: Never.self) { try WhisperModelStore.verify(in: base) }
        let before = Self.files(under: base)
        let engine = WhisperEngine(base: base)
        try await engine.prepare()
        try await engine.warmUp()
        // A hub fallback would write files (or hub metadata) under the download base.
        #expect(Self.files(under: base) == before)
        let expected = Set(
            (WhisperModelManifest.model.map { WhisperModelStore.modelFolder(in: base).appending(path: $0.path) }
                + WhisperModelManifest.tokenizer.map {
                    WhisperModelStore.tokenizerFolder(in: base).appending(path: $0.path)
                }).map { $0.resolvingSymlinksInPath().path })
        #expect(before.filter { !$0.contains("/.cache/huggingface/") } == expected)
    }

    /// Every regular file below `folder`, with symlinks resolved (the temporary folder lies below /private).
    static func files(under folder: URL) -> Set<String> {
        guard
            let walker = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [])
        else { return [] }
        var paths: Set<String> = []
        for case let url as URL in walker
        where (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
            paths.insert(url.resolvingSymlinksInPath().path)
        }
        return paths
    }
}
