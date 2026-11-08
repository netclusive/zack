import Foundation

/// snippets.txt: `name => text`, the text escaped as in `SnippetFile.escaped`.
public enum SnippetFormat: EntryFormat {
    public static func kind(of line: String) -> LineKind<Snippet> {
        let (trimmed, common) = commonKind(of: line)
        if let common { return common }
        guard let arrow = trimmed.range(of: "=>") else { return .unreadable }
        let name = trimmed[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        let text = SnippetFile.unescaped(trimmed[arrow.upperBound...].trimmingCharacters(in: .whitespaces))
        guard !name.isEmpty, !text.isEmpty else { return .unreadable }
        return .entry(Snippet(name: name, text: text))
    }

    public static func line(for entry: Snippet) -> String {
        let name = entry.name.trimmingCharacters(in: .whitespaces)
        let text = SnippetFile.escaped(entry.text.trimmingCharacters(in: .whitespaces))
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
