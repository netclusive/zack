import CryptoKit
import Foundation
import ZackCore

/// The Parakeet Ultra files Zack was measured with: one Hugging Face commit and size and SHA-256 of every file.
public enum ParakeetModelManifest {
    public struct File: Equatable, Sendable {
        /// Relative to the model folder.
        public let path: String
        public let size: Int
        public let sha256: String
    }

    /// Commit of FluidInference/parakeet-ultra-coreml (`main` since 2026-09-24); the installed copy all measurements
    /// ran with matched it file by file on 2026-11-06.
    public static let ultraRevision = "95eaa59a39d4394f047a4dc5cce480388a60d1b6"

    /// Every file of the commit Zack loads or keeps; the repository's README and .gitattributes are not downloaded.
    public static let ultra: [File] = [
        File(
            path: "Decoder.mlmodelc/analytics/coremldata.bin", size: 243,
            sha256: "fe92b6cfaa012abd5248c0bc877832f19807015abffc60d87b8ccc8ccb48b3b5"),
        File(
            path: "Decoder.mlmodelc/coremldata.bin", size: 560,
            sha256: "3b06e66768f0df7e21795f50e2b29300e33eeb1a2579dc42c695279c2d308497"),
        File(
            path: "Decoder.mlmodelc/model.mil", size: 13110,
            sha256: "956f600207f88396017ca5c96cfa3acd5bfee60835a5b44b762e033a8fb28955"),
        File(
            path: "Decoder.mlmodelc/weights/weight.bin", size: 23_604_992,
            sha256: "02a0d219f281b9665bc10c8768649403b2eebbbf4b44c627041d948e0de11bb4"),
        File(
            path: "Encoder.mlmodelc/analytics/coremldata.bin", size: 243,
            sha256: "d87101d824d6723cf95304da33755c3c60e762663b9ef2b0c4bd0aa166a09a0d"),
        File(
            path: "Encoder.mlmodelc/coremldata.bin", size: 514,
            sha256: "397a84a4062f563cbc5f56077c674f09a61d85be5090f61d2f1932afb92ac0fe"),
        File(
            path: "Encoder.mlmodelc/model.mil", size: 1_002_653,
            sha256: "f5d601568a4171d99a314c0fe3f6bc67715da2623732a3fb566e050ea83e5848"),
        File(
            path: "Encoder.mlmodelc/weights/weight.bin", size: 594_211_328,
            sha256: "315ba01f33cadbf601d43ac7f5c86208b7aa75fdaa34705c9869d5abe3521c9b"),
        File(
            path: "JointDecisionv3.mlmodelc/analytics/coremldata.bin", size: 243,
            sha256: "68d38ca646aebafa7a9329e2efda50f5767c49e89fdb5f77f212072bb66f97c4"),
        File(
            path: "JointDecisionv3.mlmodelc/coremldata.bin", size: 592,
            sha256: "5e3af5a4ce686f6c237cadbd9284e10d333bc0e1546633cd0e430e6194044bc4"),
        File(
            path: "JointDecisionv3.mlmodelc/model.mil", size: 11777,
            sha256: "791b3c3cf3eb2079c84623fc880f6bba008d1366e5f8b03e9a8ed8bd4d7194a0"),
        File(
            path: "JointDecisionv3.mlmodelc/weights/weight.bin", size: 12_642_764,
            sha256: "3f310b85b82341c53ec383025ab094a4e462ee1c592e1ad7c6bfe39cff66ca25"),
        File(
            path: "Preprocessor.mlmodelc/analytics/coremldata.bin", size: 243,
            sha256: "c9beeb989c8d66f8be11df59bc6df277ec76cee404f6865b46243835ef562f6d"),
        File(
            path: "Preprocessor.mlmodelc/coremldata.bin", size: 486,
            sha256: "dbde3f2300842c1fd51ef3ff948a0bcffe65ffd2dca10707f2509f32c1d65b1d"),
        File(
            path: "Preprocessor.mlmodelc/metadata.json", size: 2841,
            sha256: "2a98699e22d279dd37fa1d238aeb1c6db1df0d6fad687775324157689d8f3acf"),
        File(
            path: "Preprocessor.mlmodelc/model.mil", size: 28181,
            sha256: "4b8518a956450fec57f06c2a21bdffc26973f7f1fa6842fb38fe917f896b6b93"),
        File(
            path: "Preprocessor.mlmodelc/weights/weight.bin", size: 491_072,
            sha256: "129b76e3aeafa8afa3ea76d995b964b145fe83700d579f6ff42c4c38fa0968ea"),
        File(
            path: "config.json", size: 414,
            sha256: "965c69bf500c7be18958df6438dc1ba897721690ae412937ca7c91e28cec1870"),
        File(
            path: "parakeet_v3_vocab.json", size: 151_122,
            sha256: "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"),
        File(
            path: "parakeet_vocab.json", size: 151_122,
            sha256: "7ec60e05f1b24480736ec0eed40900f4626bce1fa9a60fd700ec7e2a59198735"),
    ]

    /// Throws `ZackError.modelUnverified` with the first file that is missing, has another size or other content.
    public static func verify(_ files: [File], in folder: URL) throws {
        for file in files {
            let url = folder.appending(path: file.path, directoryHint: .notDirectory)
            guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size == file.size,
                (try? sha256(of: url)) == file.sha256
            else { throw ZackError.modelUnverified(file.path) }
        }
    }

    /// Reads in 1 MB chunks, so the 594 MB encoder never sits in memory as a whole.
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
