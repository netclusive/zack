import Foundation

/// Shared location for downloaded model weights, kept out of ~/Documents (may sync to iCloud).
public enum ModelStorage {
    /// `~/Library/Application Support/Zack/Models`.
    public static func directory(createIfNeeded: Bool) throws -> URL {
        let url = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )
        .appending(path: "Zack/Models", directoryHint: .isDirectory)
        if createIfNeeded {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
        return url
    }
}
