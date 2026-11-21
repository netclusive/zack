import Foundation

/// German times with hours and minutes as "16:45 Uhr": Parakeet's "16.45 Uhr", "16 Uhr 45" and spoken words alike.
/// A range "14:30 Uhr bis 15:40 Uhr" keeps "Uhr" once. Times without minutes and "halb acht" stay as they are.
public struct TimeRule: TextRule {
    // "16.45 Uhr": an hour from 0 to 23, two-digit minutes, then "Uhr".
    private static let written = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}.,:])([01]?\d|2[0-3])\.([0-5]\d)(?=[ \t]+Uhr(?![\p{L}\p{N}]))"#)
    // "<hour> Uhr <minutes>" with digits or words. The minutes must end the clause or be followed by a lower-case
    // word: a capitalised word after them is a noun the number counts ("um zehn Uhr drei Personen").
    private static let spoken = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}.,:])(\p{L}+|\d{1,2}) Uhr ((?:[Nn]ull )?\p{L}+|\d{1,2})(?![\p{L}\p{N}])"#
            + #"(?=$|\r?\n|[^\s\p{L}\p{N}]|[ \t]+\p{Ll})"#)
    private static let range = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}.,:])(\d{1,2}:\d{2}) Uhr bis (\d{1,2}:\d{2}) Uhr(?![\p{L}\p{N}])"#)

    public init() {}

    public func apply(_ text: String, context: RuleContext) -> String {
        guard context.language == .german else { return text }
        var result = Self.written.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1:$2")
        result = Self.replacingSpoken(in: result)
        return Self.range.stringByReplacingMatches(
            in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1 bis $2 Uhr")
    }

    private static func replacingSpoken(in text: String) -> String {
        var result = text
        for match in spoken.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: result), let hourRange = Range(match.range(at: 1), in: result),
                let minuteRange = Range(match.range(at: 2), in: result),
                let hour = hour(String(result[hourRange])), let minute = minute(String(result[minuteRange]))
            else { continue }
            result.replaceSubrange(whole, with: "\(hour):\(minute < 10 ? "0" : "")\(minute) Uhr")
        }
        return result
    }

    /// 0 to 23 as digits or a word; "ein Uhr" is one o'clock.
    private static func hour(_ token: String) -> Int? {
        let value = Int(token) ?? (token.lowercased() == "ein" ? 1 : GermanNumber.value(of: token))
        return value.flatMap { (0...23).contains($0) ? $0 : nil }
    }

    /// 0 to 59 as digits, 1 to 59 as a word, or "null" and a word from 1 to 9.
    private static func minute(_ token: String) -> Int? {
        if let value = Int(token) { return value < 60 ? value : nil }
        let words = token.split(separator: " ").map(String.init)
        if words.count == 2 {
            guard words[0].lowercased() == "null", let value = GermanNumber.value(of: words[1]), (1...9).contains(value)
            else { return nil }
            return value
        }
        return GermanNumber.value(of: token).flatMap { (1...59).contains($0) ? $0 : nil }
    }
}
