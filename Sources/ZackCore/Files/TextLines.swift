/// A text split into lines that keep their own terminators, so untouched lines stay byte for byte.
public struct TextLines: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public var content: String
        public var terminator: String

        public init(content: String, terminator: String) {
            self.content = content
            self.terminator = terminator
        }
    }

    public private(set) var lines: [Line]

    public init(_ text: String) {
        var lines: [Line] = []
        var content = ""
        for character in text {
            if character.isNewline {
                lines.append(Line(content: content, terminator: String(character)))
                content = ""
            } else {
                content.append(character)
            }
        }
        if !content.isEmpty { lines.append(Line(content: content, terminator: "")) }
        self.lines = lines
    }

    public var text: String {
        lines.reduce(into: "") { $0 += $1.content + $1.terminator }
    }

    /// Replaces the content of one line, keeping its terminator.
    public mutating func replace(at index: Int, with content: String) {
        lines[index].content = content
    }

    /// Appends a line using the file's terminator; a missing final break is added first.
    public mutating func append(_ content: String) {
        let terminator = lines.last(where: { !$0.terminator.isEmpty })?.terminator ?? "\n"
        if let last = lines.indices.last, lines[last].terminator.isEmpty {
            lines[last].terminator = terminator
        }
        lines.append(Line(content: content, terminator: terminator))
    }

    /// Removes one line together with its terminator.
    public mutating func remove(at index: Int) {
        lines.remove(at: index)
    }
}
