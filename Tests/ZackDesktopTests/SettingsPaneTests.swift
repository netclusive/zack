import Testing

@testable import ZackDesktop

struct SettingsPaneTests {
    @Test func paneTitlesAndIconsMatchTheSpec() {
        #expect(
            SettingsPane.allCases.map(\.title) == [
                "Allgemein", "Wörterbuch", "Textbausteine", "Code-Apps", "Updates", "Einrichtung",
            ])
        #expect(
            SettingsPane.allCases.map(\.icon) == [
                "lucide-settings", "lucide-book-a", "lucide-text-quote", "lucide-code", "lucide-refresh-cw",
                "lucide-shield-check",
            ])
    }
}
