import Foundation

public struct ResolvedContext: Equatable, Sendable {
    public var text: String?
    public var source: ContextResolver.Source

    public init(text: String?, source: ContextResolver.Source) {
        self.text = text
        self.source = source
    }
}

public enum ContextResolver {
    public static let maxCharacters = 500

    public enum Source: String, Sendable { case ax, memory, none }

    /// The window of at most `maxCharacters` UTF-16 units that ends at the cursor.
    public static func readRange(before location: Int) -> TextRange {
        let start = max(0, location - maxCharacters)
        return TextRange(location: start, length: location - start)
    }

    /// Last `maxCharacters` characters, cut to the current line (including its newline).
    public static func trim(_ text: String) -> String {
        var text = Substring(text)
        // A read that began inside a surrogate pair starts with U+FFFD.
        if text.first == "\u{FFFD}" { text = text.dropFirst() }
        text = text.suffix(maxCharacters)
        if let newline = text.lastIndex(where: \.isNewline) { text = text[newline...] }
        return String(text)
    }

    /// Accessibility text (an empty field included) wins over the memory of the last insert, except that an empty
    /// text gives way to a memory with text: VS Code reports "" for a line with content, and clearing a
    /// real field takes keys, which drop the memory.
    public static func resolve(_ snapshot: FocusSnapshot, memory: String?) -> ResolvedContext {
        if let text = snapshot.textBeforeCursor, !text.isEmpty || (memory ?? "").isEmpty {
            return ResolvedContext(text: text, source: .ax)
        }
        if let memory { return ResolvedContext(text: memory, source: .memory) }
        return ResolvedContext(text: nil, source: .none)
    }
}
