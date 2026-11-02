import Foundation

/// Interface texts of this package, looked up in its string catalog.
enum UIText {
    /// Overrides the lookup language; tests set it.
    @TaskLocal static var locale: Locale?

    /// Resolves a text in the package catalog. The language follows the one macOS chose for the app unless `locale` is set.
    static func localized(_ value: String.LocalizationValue) -> String {
        var resource = LocalizedStringResource(value, bundle: .atURL(Bundle.module.bundleURL))
        resource.locale = locale ?? Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en")
        return String(localized: resource)
    }
}
