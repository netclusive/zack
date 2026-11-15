import CryptoKit
import Foundation

/// Size and SHA-256 of the model files Zack was measured with, and the check against them.
public enum ModelManifest {
    public struct File: Equatable, Sendable {
        /// Relative to the model folder.
        public let path: String
        public let size: Int
        public let sha256: String

        public init(path: String, size: Int, sha256: String) {
            self.path = path
            self.size = size
            self.sha256 = sha256
        }
    }

    /// Throws `ZackError.modelUnverified` with the first file that is missing, has another size or other content.
    public static func verify(_ files: [File], in folder: URL) throws {
        for file in files {
            let url = folder.appending(path: file.path, directoryHint: .notDirectory)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == file.size,
                (try? sha256(of: url)) == file.sha256
            else { throw ZackError.modelUnverified(file.path) }
        }
    }

    /// Reads in 1 MB chunks, so large weight files never sit in memory as a whole.
    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hash.update(data: chunk)
        }
        return hash.finalize().map { byte in
            let digits = String(byte, radix: 16)
            return digits.count == 1 ? "0" + digits : digits
        }.joined()
    }
}
