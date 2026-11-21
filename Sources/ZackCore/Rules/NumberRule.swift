import Foundation

/// German numbers from 13 as digits ("246", "5000", "12.500"); one to twelve stay words. Decimals become digits
/// whatever their size ("3,5"). A number Parakeet splits into two words ("fünftausend zweihundertsechsundvierzig")
/// counts as one. Ordinals, compounds ("Zwanzigjährige") and a lone "hundert" or "tausend" ("Tausend Dank") stay.
public struct NumberRule: TextRule {
    static let firstInDigits = 13
    /// A whole word or integer, not part of a compound, a hyphenated word or a written number such as "3,5".
    private static let token = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}.,:\-])(?:\p{L}+|\d+)(?![\p{L}\p{N}\-]|[.,:]\d)"#)

    public init() {}

    public func apply(_ text: String, context: RuleContext) -> String {
        guard context.language == .german else { return text }
        let source = text as NSString
        let tokens = Tokens(
            ranges: Self.token.matches(in: text, range: NSRange(location: 0, length: source.length)).map(\.range),
            text: source)
        let result = NSMutableString(string: text)
        var replacements: [(NSRange, String)] = []
        var index = 0
        while index < tokens.count {
            guard let (end, digits) = Self.number(at: index, in: tokens) else {
                index += 1
                continue
            }
            let start = tokens.ranges[index].location
            replacements.append((NSRange(location: start, length: NSMaxRange(tokens.ranges[end]) - start), digits))
            index = end + 1
        }
        for (range, digits) in replacements.reversed() { result.replaceCharacters(in: range, with: digits) }
        return result as String
    }

    /// Digits from 10 000 on in groups of three with a dot ("12.500"); below that without ("5246", "2026").
    static func format(_ value: Int) -> String {
        var digits = String(value)
        guard value >= 10_000 else { return digits }
        var groups: [String] = []
        while digits.count > 3 {
            groups.insert(String(digits.suffix(3)), at: 0)
            digits.removeLast(3)
        }
        return ([digits] + groups).joined(separator: ".")
    }

    /// The index of the last token and the written number for a number that starts at `start`.
    private static func number(at start: Int, in tokens: Tokens) -> (Int, String)? {
        let word = tokens[start]
        guard let leading = Int(word) ?? GermanNumber.value(of: word) else { return nil }
        if tokens.follows(start + 1), tokens[start + 1].lowercased() == "komma",
            let (end, decimals) = decimals(after: start + 1, in: tokens)
        {
            return (end, format(leading) + "," + decimals)
        }
        guard Int(word) == nil else { return nil }
        var value = leading
        var end = start
        var last = word.lowercased()
        while tokens.follows(end + 1), Int(tokens[end + 1]) == nil, let next = GermanNumber.value(of: tokens[end + 1]),
            next > 0,
            last.hasSuffix("tausend") && value % 1000 == 0 && next < 1000
                || last.hasSuffix("hundert") && value % 100 == 0 && next < 100
        {
            value += next
            end += 1
            last = tokens[end].lowercased()
        }
        if end == start, value < firstInDigits || last == "hundert" || last == "tausend" { return nil }
        return (end, format(value))
    }

    /// The digits after "Komma": single digits ("zwei fünf"), one number word ("fünfundzwanzig") or one integer.
    private static func decimals(after komma: Int, in tokens: Tokens) -> (Int, String)? {
        guard tokens.follows(komma + 1) else { return nil }
        if Int(tokens[komma + 1]) != nil { return (komma + 1, tokens[komma + 1]) }
        var digits = ""
        var end = komma
        while tokens.follows(end + 1), let value = GermanNumber.value(of: tokens[end + 1]) {
            if value <= 9 {
                digits += String(value)
            } else if digits.isEmpty, value < 100 {
                digits = String(value)
                end += 1
                break
            } else {
                break
            }
            end += 1
        }
        return digits.isEmpty ? nil : (end, digits)
    }

    private struct Tokens {
        let ranges: [NSRange]
        let text: NSString

        var count: Int { ranges.count }

        subscript(index: Int) -> String { text.substring(with: ranges[index]) }

        /// True if token `index` exists and a single space separates it from the token before.
        func follows(_ index: Int) -> Bool {
            guard index > 0, index < ranges.count else { return false }
            let gap = NSMaxRange(ranges[index - 1])
            return text.substring(with: NSRange(location: gap, length: ranges[index].location - gap)) == " "
        }
    }
}
