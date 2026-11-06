import FluidAudio
import Foundation
import ZackCore

/// Where Parakeet models live and whether they are complete. Only `download` uses the network.
public enum ParakeetModelStore {
    /// Folder of a variant inside a models directory (FluidAudio's repository folder name).
    public static func folderName(_ variant: ParakeetTranscriber.Variant) -> String {
        repo(variant).folderName
    }

    public static func modelFolder(_ variant: ParakeetTranscriber.Variant, in base: URL) -> URL {
        base.appending(path: folderName(variant), directoryHint: .isDirectory)
    }

    /// FluidAudio's own cache (`~/Library/Application Support/FluidAudio/Models`), used by zack-bench before 0.2.0.
    public static func fluidAudioDirectory() -> URL {
        AsrModels.defaultCacheDirectory(for: .v3).deletingLastPathComponent()
    }

    /// True if every file FluidAudio loads is present. Reads the file system only.
    public static func isComplete(_ variant: ParakeetTranscriber.Variant, in base: URL) -> Bool {
        AsrModels.modelsExist(at: modelFolder(variant, in: base), version: version(variant))
    }

    /// Paths `isComplete` checks, relative to the model folder; for tests with fake model folders.
    public static func requiredPaths(_ variant: ParakeetTranscriber.Variant) -> [String] {
        ModelNames.ASR.requiredModelsV3().sorted() + [ModelNames.ASR.vocabularyFile]
    }

    /// Downloads the variant from Hugging Face into `base`; `progress` gets 0...1 on an unspecified queue. Ultra comes
    /// from the pinned commit; `verify` checks the files afterwards.
    public static func download(
        _ variant: ParakeetTranscriber.Variant, to base: URL, progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        pinRevision(variant)
        try await AsrModels.download(to: modelFolder(variant, in: base), version: version(variant)) {
            progress($0.fractionCompleted)
        }
    }

    /// Points FluidAudio's listing and file requests for Ultra at the commit in the manifest, so a later push to the
    /// repository's `main` cannot change what a download gets. v3 (bench only) stays on FluidAudio's default.
    static func pinRevision(_ variant: ParakeetTranscriber.Variant) {
        guard variant == .ultra else { return }
        ModelRegistry.revisionOverrides[repo(variant).remotePath] = ParakeetModelManifest.ultraRevision
    }

    /// Checks every file of the variant against the manifest; v3 has none, so it never passes.
    public static func verify(_ variant: ParakeetTranscriber.Variant, in base: URL) throws {
        guard variant == .ultra else { throw ZackError.modelUnverified(variant.rawValue) }
        try ParakeetModelManifest.verify(ParakeetModelManifest.ultra, in: modelFolder(variant, in: base))
    }

    /// Loads complete local models without network access. `AsrModels.load` would delete and download again
    /// after a load error, so the app uses this path.
    static func loadLocal(_ variant: ParakeetTranscriber.Variant, from base: URL) throws -> AsrModels {
        try AsrModels.loadLocal(from: modelFolder(variant, in: base), version: version(variant))
    }

    static func version(_ variant: ParakeetTranscriber.Variant) -> AsrModelVersion {
        variant == .v3 ? .v3 : .ultra
    }

    static func repo(_ variant: ParakeetTranscriber.Variant) -> Repo {
        variant == .v3 ? .parakeetV3 : .parakeetUltra
    }
}
