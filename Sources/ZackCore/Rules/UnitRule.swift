import Foundation

/// After a number, German unit words become symbols ("5 m", "600 W", "100 Mbit/s", "13,5 %"), and a symbol gets its
/// space ("2TB" -> "2 TB"). A number word before a unit becomes digits, so "zwei Terabyte" is "2 TB"; "ein" stays an
/// article. Units of time, "Euro" and "Grad" without "Celsius" stay words, and nothing changes without a number.
/// Unit words match in any case and with "Byte" or "Bit" written apart ("tebi byte"); Parakeet's "TB Byte" for a
/// binary prefix becomes "TiB".
public struct UnitRule: TextRule {
    private struct Unit {
        let symbol: String
        let words: [String]
        /// "pro Sekunde" or "pro Stunde" after the word becomes "/s" or "/h".
        var per: String?
    }

    private static let units: [Unit] = [
        Unit(symbol: "mm", words: ["Millimeter", "Millimetern"]),
        Unit(symbol: "cm", words: ["Zentimeter", "Zentimetern"]),
        Unit(symbol: "m", words: ["Meter", "Metern"]),
        Unit(symbol: "km", words: ["Kilometer", "Kilometern"], per: "Stunde"),
        Unit(symbol: "m²", words: ["Quadratmeter", "Quadratmetern"]),
        Unit(symbol: "km²", words: ["Quadratkilometer", "Quadratkilometern"]),
        Unit(symbol: "m³", words: ["Kubikmeter", "Kubikmetern"]),
        Unit(symbol: "mg", words: ["Milligramm"]),
        Unit(symbol: "g", words: ["Gramm"]),
        Unit(symbol: "kg", words: ["Kilogramm", "Kilo"]),
        Unit(symbol: "t", words: ["Tonne", "Tonnen"]),
        Unit(symbol: "ml", words: ["Milliliter", "Millilitern"]),
        Unit(symbol: "l", words: ["Liter", "Litern"]),
        Unit(symbol: "bit", words: ["Bit", "Bits"], per: "Sekunde"),
        Unit(symbol: "kbit", words: ["Kilobit"], per: "Sekunde"),
        Unit(symbol: "Mbit", words: ["Megabit"], per: "Sekunde"),
        Unit(symbol: "Gbit", words: ["Gigabit"], per: "Sekunde"),
        Unit(symbol: "Tbit", words: ["Terabit"], per: "Sekunde"),
        Unit(symbol: "KB", words: ["Kilobyte", "Kilobytes"], per: "Sekunde"),
        Unit(symbol: "MB", words: ["Megabyte", "Megabytes"], per: "Sekunde"),
        Unit(symbol: "GB", words: ["Gigabyte", "Gigabytes"], per: "Sekunde"),
        Unit(symbol: "TB", words: ["Terabyte", "Terabytes"], per: "Sekunde"),
        Unit(symbol: "PB", words: ["Petabyte", "Petabytes"], per: "Sekunde"),
        // "Maybibyte" and "Gibbibyte" are how Parakeet heard Sven say Mebibyte and Gibibyte.
        Unit(symbol: "KiB", words: ["Kibibyte"], per: "Sekunde"),
        Unit(symbol: "MiB", words: ["Mebibyte", "Maybibyte"], per: "Sekunde"),
        Unit(symbol: "GiB", words: ["Gibibyte", "Gibbibyte"], per: "Sekunde"),
        Unit(symbol: "TiB", words: ["Tebibyte"], per: "Sekunde"),
        Unit(symbol: "PiB", words: ["Pebibyte"], per: "Sekunde"),
        Unit(symbol: "Hz", words: ["Hertz"]),
        Unit(symbol: "kHz", words: ["Kilohertz"]),
        Unit(symbol: "MHz", words: ["Megahertz"]),
        Unit(symbol: "GHz", words: ["Gigahertz"]),
        Unit(symbol: "mW", words: ["Milliwatt"]),
        Unit(symbol: "W", words: ["Watt"]),
        Unit(symbol: "kW", words: ["Kilowatt"]),
        Unit(symbol: "MW", words: ["Megawatt"]),
        Unit(symbol: "Wh", words: ["Wattstunde", "Wattstunden"]),
        Unit(symbol: "kWh", words: ["Kilowattstunde", "Kilowattstunden"]),
        Unit(symbol: "MWh", words: ["Megawattstunde", "Megawattstunden"]),
        Unit(symbol: "mV", words: ["Millivolt"]),
        Unit(symbol: "V", words: ["Volt"]),
        Unit(symbol: "kV", words: ["Kilovolt"]),
        Unit(symbol: "mA", words: ["Milliampere"]),
        Unit(symbol: "A", words: ["Ampere"]),
        Unit(symbol: "mAh", words: ["Milliamperestunde", "Milliamperestunden"]),
        Unit(symbol: "%", words: ["Prozent"]),
        Unit(symbol: "°C", words: ["Grad Celsius"]),
    ]
    private static let byWord = Dictionary(
        uniqueKeysWithValues: units.flatMap { unit in unit.words.map { (key($0), unit) } })
    private static let bySymbol = Dictionary(uniqueKeysWithValues: units.map { ($0.symbol, $0) })
    /// Parakeet writes a binary prefix as the decimal symbol and "Byte", e.g. "TB Byte" for Tebibyte.
    private static let binary = ["KB": "KiB", "MB": "MiB", "GB": "GiB", "TB": "TiB", "PB": "PiB"]
    /// Symbols that get a space when written right after the number; single letters such as "m" stay as written.
    private static let spaced = units.map(\.symbol).filter { $0.count > 1 || $0 == "%" }

    private static let number = #"(?<![\p{L}\p{N}.,:\-])(\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:,\d+)?"#
    private static let wordPatterns = units.flatMap(\.words).sorted { $0.count > $1.count }.map(pattern)
    private static let spoken = try! NSRegularExpression(
        pattern: number + #"|\p{L}+) ("# + wordPatterns.joined(separator: "|")
            + #")(?: pro (Sekunde|Stunde))?(?![\p{L}\p{N}\-])"#,
        options: [.caseInsensitive])
    private static let glued = try! NSRegularExpression(
        pattern: number + #")("# + alternatives(spaced) + #")(?![\p{L}\p{N}])"#)
    /// A symbol after a number word, with "Byte" for a binary prefix, or with "pro Sekunde" or "pro Stunde".
    private static let symbolic = try! NSRegularExpression(
        pattern: number + #"|\p{L}+) ("# + alternatives(spaced)
            + #")(?:[ -]([Bb]ytes?))?(?: pro (Sekunde|Stunde))?(?![\p{L}\p{N}\-])"#)

    private static func alternatives(_ words: some Collection<String>) -> String {
        words.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
    }

    /// Lower case without spaces and hyphens, so "Gibi Byte", "Gibi-Byte" and "gibibyte" are one unit word.
    private static func key(_ word: String) -> String {
        word.lowercased().filter { $0 != " " && $0 != "-" }
    }

    /// A unit word as a pattern; a prefixed "byte" or "bit" may also be written apart or with a hyphen.
    private static func pattern(_ word: String) -> String {
        for suffix in ["bytes", "byte", "bits", "bit"] where word.lowercased().hasSuffix(suffix) {
            guard word.count > suffix.count else { break }
            return NSRegularExpression.escapedPattern(for: String(word.dropLast(suffix.count))) + "[ -]?"
                + NSRegularExpression.escapedPattern(for: String(word.suffix(suffix.count)))
        }
        return NSRegularExpression.escapedPattern(for: word)
    }

    public init() {}

    public func apply(_ text: String, context: RuleContext) -> String {
        guard context.language == .german else { return text }
        let spaced = Self.glued.stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "$1 $2")
        var result = spaced
        for match in Self.spoken.matches(in: spaced, range: NSRange(spaced.startIndex..., in: spaced)).reversed() {
            guard let whole = Range(match.range, in: result), let numberRange = Range(match.range(at: 1), in: result),
                let wordRange = Range(match.range(at: 2), in: result),
                let unit = Self.byWord[Self.key(String(result[wordRange]))],
                let digits = Self.digits(String(result[numberRange]))
            else { continue }
            let per = Range(match.range(at: 3), in: result).map { String(result[$0]) }
            result.replaceSubrange(whole, with: digits + " " + Self.symbol(unit, per: per))
        }
        return Self.replacingSymbols(in: result)
    }

    /// A number word before a symbol becomes digits, "TB Byte" becomes "TiB" and "MB pro Sekunde" becomes "MB/s".
    private static func replacingSymbols(in text: String) -> String {
        var result = text
        for match in symbolic.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let whole = Range(match.range, in: result), let numberRange = Range(match.range(at: 1), in: result),
                let symbolRange = Range(match.range(at: 2), in: result),
                let digits = digits(String(result[numberRange]))
            else { continue }
            var symbol = String(result[symbolRange])
            if Range(match.range(at: 3), in: result) != nil {
                guard let binary = binary[symbol] else { continue }
                symbol = binary
            }
            guard let unit = bySymbol[symbol] else { continue }
            let per = Range(match.range(at: 4), in: result).map { String(result[$0]) }
            let written = digits + " " + Self.symbol(unit, per: per)
            if written != String(result[whole]) { result.replaceSubrange(whole, with: written) }
        }
        return result
    }

    /// The symbol, with "/s" or "/h" if "pro Sekunde" or "pro Stunde" fits the unit; otherwise the words stay.
    private static func symbol(_ unit: Unit, per: String?) -> String {
        guard let per else { return unit.symbol }
        guard per.lowercased() == unit.per?.lowercased() else { return unit.symbol + " pro " + per }
        return unit.symbol + (per.lowercased() == "sekunde" ? "/s" : "/h")
    }

    /// The number as written if it is in digits, else the digits of a number word.
    private static func digits(_ number: String) -> String? {
        guard number.first?.isLetter == true else { return number }
        return GermanNumber.value(of: number).map(NumberRule.format)
    }
}
