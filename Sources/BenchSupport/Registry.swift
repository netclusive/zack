import Foundation
import ZackApple
import ZackCore
import ZackParakeet

/// Creates a cleaner for `--cleaner`; bench variants register extra ones.
public typealias CleanerFactory = @Sendable () -> any Cleaner

struct Registry: Sendable {
    static let transcriberIDs =
        AppleTranscriber.Kind.allCases.map(\.rawValue)
        + ParakeetTranscriber.Variant.allCases.map(\.rawValue)
    static let builtInCleanerIDs = ["none", "apple-fm"]

    let extraCleaners: [String: CleanerFactory]

    init(extraCleaners: [String: CleanerFactory] = [:]) {
        precondition(
            Set(extraCleaners.keys).isDisjoint(with: Self.builtInCleanerIDs), "extra cleaner shadows a built-in id")
        self.extraCleaners = extraCleaners
    }

    var cleanerIDs: [String] { Self.builtInCleanerIDs + extraCleaners.keys.sorted() }

    static func transcriber(_ id: String, language: DictationLanguage = .german) throws -> any Transcriber {
        if let kind = AppleTranscriber.Kind(rawValue: id) {
            return AppleTranscriber(kind: kind, locale: Locale(identifier: language == .english ? "en-US" : "de-DE"))
        }
        if let variant = ParakeetTranscriber.Variant(rawValue: id) { return ParakeetTranscriber(variant: variant) }
        throw ArgumentError.invalidValue(option: "--transcriber", value: id, allowed: transcriberIDs)
    }

    func cleaner(_ id: String) throws -> (any Cleaner)? {
        switch id {
        case "none": return nil
        case "apple-fm": return AppleFoundationCleaner()
        default:
            guard let factory = extraCleaners[id] else {
                throw ArgumentError.invalidValue(option: "--cleaner", value: id, allowed: cleanerIDs)
            }
            return factory()
        }
    }
}
