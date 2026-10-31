import Foundation
import ZackCore

/// Apps in which dictation runs in code mode, parsed from `code-apps.txt` (one bundle ID per line).
public struct CodeApps: Equatable, Sendable {
    public enum Match: Equatable, Sendable { case none, exact, prefix }

    private let exactIDs: Set<String>
    private let prefixes: [String]

    public init(parsing text: String) {
        var exact = Set<String>()
        var prefixes = [String]()
        for line in text.split(whereSeparator: \.isNewline) {
            let entry = line.trimmingCharacters(in: .whitespaces).lowercased()
            guard !entry.isEmpty, !entry.hasPrefix("#") else { continue }
            if entry.hasSuffix("*") {
                let prefix = String(entry.dropLast())
                if !prefix.isEmpty { prefixes.append(prefix) }
            } else {
                exact.insert(entry)
            }
        }
        exactIDs = exact
        self.prefixes = prefixes
    }

    public func match(_ bundleID: String) -> Match {
        let id = bundleID.lowercased()
        if exactIDs.contains(id) { return .exact }
        return prefixes.contains { id.hasPrefix($0) } ? .prefix : .none
    }

    public func mode(for bundleID: String?) -> TextMode {
        guard let bundleID, match(bundleID) != .none else { return .prose }
        return .code
    }

    /// Adds the ID as its own line, or removes its exact lines; prefix matches stay unchanged.
    public static func toggled(_ bundleID: String, in text: String) -> String {
        switch CodeApps(parsing: text).match(bundleID) {
        case .prefix:
            return text
        case .none:
            let separator = text.last?.isNewline ?? true ? "" : "\n"
            return text + separator + bundleID + "\n"
        case .exact:
            let id = bundleID.lowercased()
            var result = ""
            for line in lines(of: text) {
                if line.content.trimmingCharacters(in: .whitespaces).lowercased() == id { continue }
                result += line.content + line.terminator
            }
            return result.isEmpty || result.last?.isNewline == true ? result : result + "\n"
        }
    }

    /// Splits into lines keeping each line's own terminator ("\n", "\r\n"), so untouched lines stay byte for byte.
    private static func lines(of text: String) -> [(content: String, terminator: String)] {
        var lines: [(String, String)] = []
        var content = ""
        for character in text {
            if character.isNewline {
                lines.append((content, String(character)))
                content = ""
            } else {
                content.append(character)
            }
        }
        if !content.isEmpty { lines.append((content, "")) }
        return lines
    }
}
