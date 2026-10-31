import Foundation

public enum LineKind<Entry: Equatable & Sendable>: Equatable, Sendable {
    case blank
    case comment
    case entry(Entry)
    case unreadable
}

public enum EntryField: Equatable, Hashable, Sendable {
    case spelling
    case heardAs
    case name
    case text
    case bundleID
}

public enum EntryProblem: Equatable, Sendable {
    case empty
    case arrow
    case leadingHash
    case lineBreak
}

public struct EntryIssue: Equatable, Sendable {
    public let field: EntryField
    public let problem: EntryProblem

    public init(field: EntryField, problem: EntryProblem) {
        self.field = field
        self.problem = problem
    }
}

/// Describes how one kind of user file maps lines to entries.
public protocol EntryFormat {
    associatedtype Entry: Equatable & Sendable
    static func kind(of line: String) -> LineKind<Entry>
    /// Must never contain a line break for an entry without issues.
    static func line(for entry: Entry) -> String
    static func issues(in entry: Entry) -> [EntryIssue]
    /// Entries with the same key count as duplicates.
    static func key(for entry: Entry) -> String
    /// Text the search field matches against, case-insensitively.
    static func searchText(for entry: Entry) -> String
}

extension EntryFormat {
    /// Shared handling of blank and comment lines; nil means the format decides.
    static func commonKind(of line: String) -> (trimmed: String, kind: LineKind<Entry>?) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return (trimmed, .blank) }
        if trimmed.hasPrefix("#") { return (trimmed, .comment) }
        return (trimmed, nil)
    }

    /// Problems of one trimmed field; `leadingHash` only applies where the field starts the line.
    static func fieldIssues(
        _ field: EntryField, _ value: String, allowEmpty: Bool = false, checkHash: Bool = false
    ) -> [EntryIssue] {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        var issues: [EntryIssue] = []
        if trimmed.isEmpty {
            if !allowEmpty { issues.append(EntryIssue(field: field, problem: .empty)) }
            return issues
        }
        if trimmed.contains(where: \.isNewline) { issues.append(EntryIssue(field: field, problem: .lineBreak)) }
        if trimmed.contains("=>") { issues.append(EntryIssue(field: field, problem: .arrow)) }
        if checkHash, trimmed.hasPrefix("#") { issues.append(EntryIssue(field: field, problem: .leadingHash)) }
        return issues
    }
}

/// A user file seen as entries; every other line (comments, blanks, unreadable) stays untouched.
public struct EntryDocument<Format: EntryFormat>: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public let line: Int
        public let entry: Format.Entry
        public var id: Int { line }
    }

    public private(set) var lines: TextLines

    public init(text: String) {
        lines = TextLines(text)
    }

    public var text: String { lines.text }

    public var items: [Item] {
        lines.lines.enumerated().compactMap { index, line in
            if case .entry(let entry) = Format.kind(of: line.content) { return Item(line: index, entry: entry) }
            return nil
        }
    }

    public func items(matching query: String) -> [Item] {
        let all = items
        guard !query.isEmpty else { return all }
        return all.filter { Format.searchText(for: $0.entry).localizedCaseInsensitiveContains(query) }
    }

    public var unreadableCount: Int {
        lines.lines.filter { Format.kind(of: $0.content) == .unreadable }.count
    }

    /// Lines whose key already appeared on an earlier line.
    public var laterDuplicates: Set<Int> {
        var seen: Set<String> = []
        var later: Set<Int> = []
        for item in items where !seen.insert(Format.key(for: item.entry)).inserted {
            later.insert(item.line)
        }
        return later
    }

    /// Callers validate with `Format.issues(in:)` first, so the written line holds no line break.
    public mutating func replace(line: Int, with entry: Format.Entry) {
        lines.replace(at: line, with: Format.line(for: entry))
    }

    /// Callers validate with `Format.issues(in:)` first, so the written line holds no line break.
    public mutating func append(_ entry: Format.Entry) {
        lines.append(Format.line(for: entry))
    }

    public mutating func remove(line: Int) {
        lines.remove(at: line)
    }
}
