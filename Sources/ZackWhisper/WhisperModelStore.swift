import Foundation
import WhisperKit
import ZackCore

/// Where the Whisper model and its tokenizer live and whether they are complete. Only `download` uses the network.
public enum WhisperModelStore {
    /// The variant folder in the hub layout WhisperKit reads (`<base>/models/<repo>/openai_whisper-<variant>`).
    public static func modelFolder(in base: URL) -> URL {
        repoFolder(WhisperModelManifest.modelRepo, in: base)
            .appending(path: "openai_whisper-\(WhisperModelManifest.variant)", directoryHint: .isDirectory)
    }

    /// The tokenizer's hub folder, which WhisperKit searches first when its tokenizer folder is `base`.
    public static func tokenizerFolder(in base: URL) -> URL {
        repoFolder(WhisperModelManifest.tokenizerRepo, in: base)
    }

    /// True if every manifest file is present. Reads the file system only; sizes and content are `verify`'s job.
    public static func isComplete(in base: URL) -> Bool {
        files(in: base).allSatisfy { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Checks model and tokenizer against the manifest; throws `ZackError.modelUnverified` with the first difference.
    public static func verify(in base: URL) throws {
        try ModelManifest.verify(WhisperModelManifest.model, in: modelFolder(in: base))
        try ModelManifest.verify(WhisperModelManifest.tokenizer, in: tokenizerFolder(in: base))
    }

    /// Deletes the variant folder, its download metadata and the tokenizer folder; other models stay.
    public static func remove(from base: URL) throws {
        let metadata = repoFolder(WhisperModelManifest.modelRepo, in: base)
            .appending(path: ".cache/huggingface/download/openai_whisper-\(WhisperModelManifest.variant)")
        for folder in [modelFolder(in: base), metadata, tokenizerFolder(in: base)]
        where FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    /// Downloads tokenizer and model from the pinned commits into `base`; `progress` gets 0...1, weighted by size, on
    /// an unspecified queue. Present and valid files are kept. `verify` checks the result.
    public static func download(to base: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
        let tokenizerBytes = Double(WhisperModelManifest.tokenizer.reduce(0) { $0 + $1.size })
        let modelBytes = Double(WhisperModelManifest.model.reduce(0) { $0 + $1.size })
        let total = tokenizerBytes + modelBytes
        let tokenizer = ModelDownloader(
            repoName: WhisperModelManifest.tokenizerRepo, revision: WhisperModelManifest.tokenizerRevision)
        _ = try await tokenizer.resolveRepo(patterns: WhisperModelManifest.tokenizer.map(\.path), downloadBase: base) {
            progress($0.fractionCompleted * tokenizerBytes / total)
        }
        try Task.checkCancellation()
        let model = ModelDownloader(
            repoName: WhisperModelManifest.modelRepo, revision: WhisperModelManifest.modelRevision)
        _ = try await model.resolveRepo(
            patterns: ["openai_whisper-\(WhisperModelManifest.variant)/*"], downloadBase: base
        ) {
            progress((tokenizerBytes + $0.fractionCompleted * modelBytes) / total)
        }
    }

    private static func files(in base: URL) -> [URL] {
        WhisperModelManifest.model.map { modelFolder(in: base).appending(path: $0.path) }
            + WhisperModelManifest.tokenizer.map { tokenizerFolder(in: base).appending(path: $0.path) }
    }

    /// The hub's repository folder below a download base.
    private static func repoFolder(_ repo: String, in base: URL) -> URL {
        base.appending(path: "models", directoryHint: .isDirectory).appending(path: repo, directoryHint: .isDirectory)
    }
}
