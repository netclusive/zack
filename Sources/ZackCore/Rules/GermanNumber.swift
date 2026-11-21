/// German cardinal numbers written as one word, up to 999 999, such as "zweihundertsechsundvierzig" or
/// "neunzehnhundertneunundneunzig". Case does not matter, and "ss" counts as "ß".
enum GermanNumber {
    private static let units = [
        "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "sechs": 6, "sieben": 7, "acht": 8, "neun": 9,
    ]
    private static let words = units.merging([
        "zehn": 10, "elf": 11, "zwölf": 12, "dreizehn": 13, "vierzehn": 14, "fünfzehn": 15, "sechzehn": 16,
        "siebzehn": 17, "achtzehn": 18, "neunzehn": 19, "zwanzig": 20, "dreissig": 30, "vierzig": 40, "fünfzig": 50,
        "sechzig": 60, "siebzig": 70, "achtzig": 80, "neunzig": 90,
    ]) { first, _ in first }
    private static let tens: Set<Int> = [20, 30, 40, 50, 60, 70, 80, 90]

    /// The value, or nil for any other word. A lone "ein" is an article, not a number.
    static func value(of word: String) -> Int? {
        let word = word.lowercased().replacingOccurrences(of: "ß", with: "ss")
        switch word {
        case "null": return 0
        case "eins": return 1
        default: break
        }
        guard let range = word.range(of: "tausend") else { return belowThousand(word, centuries: true, last: true) }
        let head = String(word[..<range.lowerBound])
        let tail = String(word[range.upperBound...])
        guard let thousands = head.isEmpty ? 1 : belowThousand(head, centuries: false, last: false),
            let rest = tail.isEmpty ? 0 : belowThousand(tail, centuries: false, last: true), rest > 0 || tail.isEmpty
        else { return nil }
        return thousands * 1000 + rest
    }

    /// 1 to 999; with `centuries` the hundreds may count up to 99 as in years ("neunzehnhundert").
    /// `last` means nothing follows, so the number may end in "eins" but not in "ein".
    private static func belowThousand(_ word: String, centuries: Bool, last: Bool) -> Int? {
        guard let range = word.range(of: "hundert") else { return belowHundred(word, last: last) }
        let head = String(word[..<range.lowerBound])
        let tail = String(word[range.upperBound...])
        guard let hundreds = head.isEmpty ? 1 : belowHundred(head, last: false), hundreds <= (centuries ? 99 : 9),
            let rest = tail.isEmpty ? 0 : belowHundred(tail, last: last)
        else { return nil }
        return hundreds * 100 + rest
    }

    /// 1 to 99.
    private static func belowHundred(_ word: String, last: Bool) -> Int? {
        if let value = words[word] { return value }
        if word == (last ? "eins" : "ein") { return 1 }
        let parts = word.components(separatedBy: "und")
        guard parts.count == 2, let unit = parts[0] == "ein" ? 1 : units[parts[0]], let ten = words[parts[1]],
            tens.contains(ten)
        else { return nil }
        return unit + ten
    }
}
