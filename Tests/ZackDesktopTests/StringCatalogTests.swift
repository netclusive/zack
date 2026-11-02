import Foundation
import Testing

/// Consistency checks for the string catalogs of the packages and the app.
struct StringCatalogTests {
    /// Catalog paths relative to the repository root.
    static let catalogs = [
        "Sources/ZackUpdate/Localizable.xcstrings", "Sources/ZackDesktop/Localizable.xcstrings",
        "App/Zack/Localizable.xcstrings",
    ]

    /// Keyed by Info.plist keys, not by German text, so it is checked on its own.
    static let infoPlistCatalog = "App/Zack/InfoPlist.xcstrings"
    static let microphoneKey = "NSMicrophoneUsageDescription"

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

    static func infoPlistValue(_ key: String) throws -> String? {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent("App/Support/Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        return plist?[key] as? String
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

    @Test func infoPlistCatalogMatchesInfoPlist() throws {
        let catalog = try Self.load(Self.infoPlistCatalog)
        #expect(catalog.sourceLanguage == "de")
        #expect(Array(catalog.strings.keys) == [Self.microphoneKey])
        let localizations = catalog.strings[Self.microphoneKey]?.localizations
        let german = try #require(localizations?["de"]?.stringUnit)
        let english = try #require(localizations?["en"]?.stringUnit)
        let infoPlistText = try Self.infoPlistValue(Self.microphoneKey)
        #expect(german.state == "translated")
        #expect(german.value == infoPlistText)
        #expect(english.state == "translated")
        #expect(english.value == "Zack uses the microphone for dictation. Audio stays on this Mac.")
    }

    /// Languages without a localization of their own fall back to English.
    @Test func developmentRegionIsEnglish() throws {
        let region = try Self.infoPlistValue("CFBundleDevelopmentRegion")
        #expect(region == "en")
    }
}
