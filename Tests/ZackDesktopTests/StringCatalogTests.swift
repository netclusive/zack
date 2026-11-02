import Foundation
import Testing

/// Consistency checks for the package string catalogs.
struct StringCatalogTests {
    /// Catalog paths relative to the repository root.
    static let catalogs = ["Sources/ZackUpdate/Localizable.xcstrings"]

    struct Catalog: Decodable {
        let sourceLanguage: String
        let strings: [String: Entry]
    }

    struct Entry: Decodable {
        let shouldTranslate: Bool?
        let localizations: [String: Localization]?
    }

    struct Localization: Decodable {
        let stringUnit: Unit?
        let variations: Variations?
    }

    struct Unit: Decodable {
        let state: String
        let value: String
    }

    struct Variations: Decodable {
        let plural: [String: Variant]?
    }

    struct Variant: Decodable {
        let stringUnit: Unit?
    }

    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func load(_ path: String) throws -> Catalog {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent(path))
        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    /// Translatable entries with their units by language; plural entries yield one unit per variant name.
    static func units(of localization: Localization) -> [String: Unit] {
        if let unit = localization.stringUnit { return ["": unit] }
        var result: [String: Unit] = [:]
        for (name, variant) in localization.variations?.plural ?? [:] {
            if let unit = variant.stringUnit { result[name] = unit }
        }
        return result
    }

    static func placeholders(_ text: String) -> [String] {
        let pattern = /%(\d+\$)?(lld|ld|d|@|f)/
        return text.matches(of: pattern).map { String($0.output.0) }
    }

    @Test(arguments: catalogs)
    func sourceLanguageIsGerman(path: String) throws {
        #expect(try Self.load(path).sourceLanguage == "de")
    }

    @Test(arguments: catalogs)
    func everyEntryHasGermanAndEnglish(path: String) throws {
        for (key, entry) in try Self.load(path).strings where entry.shouldTranslate != false {
            for language in ["de", "en"] {
                guard let localization = entry.localizations?[language] else {
                    Issue.record("\(key): missing \(language)")
                    continue
                }
                let units = Self.units(of: localization)
                if localization.stringUnit == nil {
                    #expect(Set(units.keys) == ["one", "other"], "\(key): \(language) needs one and other")
                }
                if units.isEmpty { Issue.record("\(key): \(language) has no string unit") }
                for (variant, unit) in units {
                    #expect(unit.state == "translated", "\(key): \(language) \(variant) not translated")
                    #expect(!unit.value.isEmpty, "\(key): \(language) \(variant) is empty")
                }
            }
        }
    }

    @Test(arguments: catalogs)
    func germanValueIsTheKey(path: String) throws {
        for (key, entry) in try Self.load(path).strings where entry.shouldTranslate != false {
            guard let german = entry.localizations?["de"] else { continue }
            let units = Self.units(of: german)
            let value = german.stringUnit != nil ? units[""]?.value : units["other"]?.value
            #expect(value == key, "\(key): German value differs from key")
        }
    }

    @Test(arguments: catalogs)
    func placeholdersMatch(path: String) throws {
        for (key, entry) in try Self.load(path).strings where entry.shouldTranslate != false {
            guard let german = entry.localizations?["de"], let english = entry.localizations?["en"] else {
                continue
            }
            let germanUnits = Self.units(of: german)
            let englishUnits = Self.units(of: english)
            for (variant, unit) in germanUnits {
                guard let counterpart = englishUnits[variant] else { continue }
                #expect(
                    Self.placeholders(unit.value) == Self.placeholders(counterpart.value),
                    "\(key): placeholders differ in \(variant.isEmpty ? "value" : variant)")
            }
        }
    }
}
