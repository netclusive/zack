import Foundation
import ZackCore

public enum CodeAppEntry: Equatable, Sendable {
    case app(String)
    case prefix(String)
}

/// code-apps.txt: a bundle ID, or `prefix*` for all apps starting with the prefix.
public enum CodeAppsFormat: EntryFormat {
    public static func kind(of line: String) -> LineKind<CodeAppEntry> {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }
        if trimmed.hasPrefix("#") { return .comment }
        guard trimmed.hasSuffix("*") else { return .entry(.app(trimmed)) }
        let prefix = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
        return prefix.isEmpty ? .unreadable : .entry(.prefix(prefix))
    }

    public static func line(for entry: CodeAppEntry) -> String {
        switch entry {
        case .app(let id): id.trimmingCharacters(in: .whitespaces)
        case .prefix(let prefix): prefix.trimmingCharacters(in: .whitespaces) + "*"
        }
    }

    public static func issues(in entry: CodeAppEntry) -> [EntryIssue] {
        let value = text(of: entry).trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return [EntryIssue(field: .bundleID, problem: .empty)] }
        var issues: [EntryIssue] = []
        if value.hasPrefix("#") { issues.append(EntryIssue(field: .bundleID, problem: .leadingHash)) }
        if value.contains(where: \.isNewline) { issues.append(EntryIssue(field: .bundleID, problem: .lineBreak)) }
        return issues
    }

    public static func key(for entry: CodeAppEntry) -> String {
        let value = text(of: entry).trimmingCharacters(in: .whitespaces).lowercased()
        if case .prefix = entry { return "*" + value }
        return value
    }

    public static func searchText(for entry: CodeAppEntry) -> String {
        text(of: entry)
    }

    private static func text(of entry: CodeAppEntry) -> String {
        switch entry {
        case .app(let id): id
        case .prefix(let prefix): prefix
        }
    }
}
