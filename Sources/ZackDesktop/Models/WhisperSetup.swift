import Foundation
import ZackCore
import ZackWhisper

/// Checks and downloads the Whisper model for the term check. Only `download` uses the network.
public struct WhisperSetup: Sendable {
    public typealias Downloader = ModelSetup.Downloader
    /// Throws if the model under `base` differs from the checked version.
    public typealias Verifier = ModelSetup.Verifier

    /// Shown before the download: the manifest's 648 MB, as Finder counts them.
    public static var downloadSize: String { UIText.localized("etwa 650 MB") }

    public let modelsDirectory: URL
    private let downloader: Downloader
    private let verifier: Verifier

    public init(
        modelsDirectory: URL,
        downloader: @escaping Downloader = { base, progress in
            try await WhisperModelStore.download(to: base, progress: progress)
        },
        verifier: @escaping Verifier = { base in try WhisperModelStore.verify(in: base) }
    ) {
        self.modelsDirectory = modelsDirectory
        self.downloader = downloader
        self.verifier = verifier
    }

    /// `~/Library/Application Support/Zack/Models`, next to Parakeet.
    public static func standard() throws -> WhisperSetup {
        WhisperSetup(modelsDirectory: try ModelStorage.directory(createIfNeeded: false))
    }

    /// Reads the file system only; sizes and content are `verify`'s job.
    public func status() -> ModelStatus {
        WhisperModelStore.isComplete(in: modelsDirectory) ? .ready : .missing
    }

    /// Checks the copy on disk against the manifest (about 650 MB read); a copy that differs is deleted, so it is never
    /// loaded. Runs off the caller's actor.
    @concurrent public func verify() async throws {
        do {
            try verifier(modelsDirectory)
        } catch {
            try? WhisperModelStore.remove(from: modelsDirectory)
            throw error
        }
    }

    /// Downloads from Hugging Face, then verifies. Called only when the user turns the term check on.
    @concurrent public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try await downloader(modelsDirectory, progress)
        try await verify()
    }
}
