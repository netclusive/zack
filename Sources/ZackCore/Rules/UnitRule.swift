import Foundation

/// After a number, German unit words become symbols ("5 m", "600 W", "100 Mbit/s", "13,5 %"), and a symbol gets its
/// space ("2TB" -> "2 TB"). A number word before a unit becomes digits, so "zwei Terabyte" is "2 TB"; "ein" stays an
/// article. Units of time, "Euro" and "Grad" without "Celsius" stay words, and nothing changes without a number.
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
        Unit(symbol: "KiB", words: ["Kibibyte"], per: "Sekunde"),
        Unit(symbol: "MiB", words: ["Mebibyte"], per: "Sekunde"),
        Unit(symbol: "GiB", words: ["Gibibyte"], per: "Sekunde"),
        Unit(symbol: "TiB", words: ["Tebibyte"], per: "Sekunde"),
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
        uniqueKeysWithValues: units.flatMap { unit in unit.words.map { ($0, unit) } })
    /// Symbols that get a space when written right after the number; single letters such as "m" stay as written.
    private static let spaced = units.map(\.symbol).filter { $0.count > 1 || $0 == "%" }

    private static let number = #"(?<![\p{L}\p{N}.,:\-])(\d{1,3}(?:\.\d{3})+(?:,\d+)?|\d+(?:,\d+)?"#
    private static let spoken = try! NSRegularExpression(
        pattern: number + #"|\p{L}+) ("# + alternatives(byWord.keys)
            + #")(?: pro (Sekunde|Stunde))?(?![\p{L}\p{N}\-])"#)
    private static let glued = try! NSRegularExpression(
        pattern: number + #")("# + alternatives(spaced) + #")(?![\p{L}\p{N}])"#)

    private static func alternatives(_ words: some Collection<String>) -> String {
        words.sorted { $0.count > $1.count }.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
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
                let unit = Self.byWord[String(result[wordRange])], let digits = Self.digits(String(result[numberRange]))
            else { continue }
            var written = digits + " " + unit.symbol
            if let perRange = Range(match.range(at: 3), in: result) {
                let per = String(result[perRange])
                written += per == unit.per ? (per == "Sekunde" ? "/s" : "/h") : " pro " + per
            }
            result.replaceSubrange(whole, with: written)
        }
        return result
    }

    /// The number as written if it is in digits, else the digits of a number word.
    private static func digits(_ number: String) -> String? {
        guard number.first?.isLetter == true else { return number }
        return GermanNumber.value(of: number).map(NumberRule.format)
    }
}
