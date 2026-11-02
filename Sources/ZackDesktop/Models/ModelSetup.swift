import Foundation
import ZackCore
import ZackParakeet

/// State of the recognition model for the setup window.
public enum ModelStatus: Equatable, Sendable {
    case ready
    /// A complete copy from zack-bench sits in FluidAudio's cache and can be moved over.
    case adoptable
    case missing
}

/// Checks, adopts and downloads Parakeet Ultra. Only `download` uses the network.
public struct ModelSetup: Sendable {
    public typealias Downloader =
        @Sendable (_ base: URL, _ progress: @escaping @Sendable (Double) -> Void) async throws -> Void

    public static let variant = ParakeetTranscriber.Variant.ultra
    /// Shown before the download (603 MB on disk, measured 2026-10-28).
    public static var downloadSize: String { UIText.localized("etwa 600 MB") }

    public let modelsDirectory: URL
    public let legacyDirectory: URL
    private let downloader: Downloader

    public init(
        modelsDirectory: URL, legacyDirectory: URL = ParakeetModelStore.fluidAudioDirectory(),
        downloader: @escaping Downloader = { base, progress in
            try await ParakeetModelStore.download(ModelSetup.variant, to: base, progress: progress)
        }
    ) {
        self.modelsDirectory = modelsDirectory
        self.legacyDirectory = legacyDirectory
        self.downloader = downloader
    }

    /// `~/Library/Application Support/Zack/Models` and FluidAudio's cache.
    public static func standard() throws -> ModelSetup {
        ModelSetup(modelsDirectory: try ModelStorage.directory(createIfNeeded: false))
    }

    public func status() -> ModelStatus {
        if ParakeetModelStore.isComplete(Self.variant, in: modelsDirectory) { return .ready }
        if ParakeetModelStore.isComplete(Self.variant, in: legacyDirectory) { return .adoptable }
        return .missing
    }

    /// Moves the zack-bench copy over; on the same volume this is a rename, nothing is downloaded or copied.
    /// Does nothing if the target is already complete; refuses an incomplete source, so a complete copy is never replaced.
    public func adopt() throws {
        guard !ParakeetModelStore.isComplete(Self.variant, in: modelsDirectory) else { return }
        guard ParakeetModelStore.isComplete(Self.variant, in: legacyDirectory) else {
            throw ZackError.modelMissing(Self.variant.rawValue)
        }
        let source = ParakeetModelStore.modelFolder(Self.variant, in: legacyDirectory)
        let target = ParakeetModelStore.modelFolder(Self.variant, in: modelsDirectory)
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: target.path) {
            // Leftover of an interrupted download; the complete copy replaces it.
            _ = try FileManager.default.replaceItemAt(target, withItemAt: source)
        } else {
            try FileManager.default.moveItem(at: source, to: target)
        }
    }

    /// Downloads from Hugging Face. Called only by the setup window's button.
    public func download(progress: @escaping @Sendable (Double) -> Void) async throws {
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try await downloader(modelsDirectory, progress)
    }
}
