import Foundation

/// snippets.txt: `name => text`, line breaks in the text written as `\n`.
public enum SnippetFormat: EntryFormat {
    public static func kind(of line: String) -> LineKind<Snippet> {
        let (trimmed, common) = commonKind(of: line)
        if let common { return common }
        guard let arrow = trimmed.range(of: "=>") else { return .unreadable }
        let name = trimmed[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        let text = trimmed[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\\n", with: "\n")
        guard !name.isEmpty, !text.isEmpty else { return .unreadable }
        return .entry(Snippet(name: name, text: text))
    }

    public static func line(for entry: Snippet) -> String {
        let name = entry.name.trimmingCharacters(in: .whitespaces)
        let text = entry.text.trimmingCharacters(in: .whitespaces)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).joined(separator: "\\n")
        return "\(name) => \(text)"
    }

    public static func issues(in entry: Snippet) -> [EntryIssue] {
        fieldIssues(.name, entry.name, checkHash: true) + fieldIssues(.text, entry.text).filter { $0.problem == .empty }
    }

    public static func key(for entry: Snippet) -> String {
        SnippetRule.normalizedName(entry.name)
    }

    public static func searchText(for entry: Snippet) -> String {
        entry.name + " " + entry.text
    }
}
