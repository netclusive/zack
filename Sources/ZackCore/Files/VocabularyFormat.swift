import Foundation

public struct VocabularyEntry: Equatable, Sendable {
    public var spelling: String
    public var heardAs: String?

    public init(spelling: String, heardAs: String? = nil) {
        self.spelling = spelling
        self.heardAs = heardAs
    }
}

/// vocabulary.txt: `spelling` or `heardAs => spelling`.
public enum VocabularyFormat: EntryFormat {
    public static func kind(of line: String) -> LineKind<VocabularyEntry> {
        let (trimmed, common) = commonKind(of: line)
        if let common { return common }
        guard let arrow = trimmed.range(of: "=>") else { return .entry(VocabularyEntry(spelling: trimmed)) }
        let heard = trimmed[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        let spelling = trimmed[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !heard.isEmpty, !spelling.isEmpty else { return .unreadable }
        return .entry(VocabularyEntry(spelling: spelling, heardAs: heard))
    }

    public static func line(for entry: VocabularyEntry) -> String {
        let spelling = entry.spelling.trimmingCharacters(in: .whitespaces)
        guard let heard = heardAs(of: entry) else { return spelling }
        return "\(heard) => \(spelling)"
    }

    public static func issues(in entry: VocabularyEntry) -> [EntryIssue] {
        let heard = heardAs(of: entry)
        return fieldIssues(.spelling, entry.spelling, checkHash: heard == nil)
            + fieldIssues(.heardAs, heard ?? "", allowEmpty: true, checkHash: true)
    }

    public static func key(for entry: VocabularyEntry) -> String {
        entry.spelling.trimmingCharacters(in: .whitespaces)
    }

    public static func searchText(for entry: VocabularyEntry) -> String {
        entry.spelling + " " + (entry.heardAs ?? "")
    }

    /// Trimmed heard-as text; empty counts as absent.
    private static func heardAs(of entry: VocabularyEntry) -> String? {
        let heard = entry.heardAs?.trimmingCharacters(in: .whitespaces) ?? ""
        return heard.isEmpty ? nil : heard
    }
}
