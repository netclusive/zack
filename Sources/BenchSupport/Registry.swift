import Foundation
import ZackApple
import ZackCore
import ZackParakeet

enum Registry {
    static let transcriberIDs =
        AppleTranscriber.Kind.allCases.map(\.rawValue)
        + ParakeetTranscriber.Variant.allCases.map(\.rawValue)
    static let cleanerIDs = ["none", "apple-fm"]

    static func transcriber(_ id: String, language: DictationLanguage = .german) throws -> any Transcriber {
        if let kind = AppleTranscriber.Kind(rawValue: id) {
            return AppleTranscriber(kind: kind, locale: Locale(identifier: language == .english ? "en-US" : "de-DE"))
        }
        if let variant = ParakeetTranscriber.Variant(rawValue: id) { return ParakeetTranscriber(variant: variant) }
        throw ArgumentError.invalidValue(option: "--transcriber", value: id, allowed: transcriberIDs)
    }

    static func cleaner(_ id: String) throws -> (any Cleaner)? {
        switch id {
        case "none": return nil
        case "apple-fm": return AppleFoundationCleaner()
        default: throw ArgumentError.invalidValue(option: "--cleaner", value: id, allowed: cleanerIDs)
        }
    }
}
