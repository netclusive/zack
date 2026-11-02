import Foundation
import Testing

/// Package texts must go through `UIText.localized(_:)`: these calls would look up the main bundle at runtime.
struct PackageTextLookupTests {
    static let sourceTrees = ["Sources/ZackDesktop", "Sources/ZackUpdate"]
    static let forbidden = ["String(localized:", "Text(\"", "LocalizedStringKey", "LocalizedStringResource("]

    /// Simple textual check: lines starting with `//` are skipped; other occurrences (strings, block comments) count.
    @Test(arguments: sourceTrees)
    func noMainBundleLookupsOutsideUIText(tree: String) throws {
        let root = StringCatalogTests.repoRoot.appendingPathComponent(tree)
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var scanned = 0
        for case let url as URL in files where url.pathExtension == "swift" && url.lastPathComponent != "UIText.swift" {
            scanned += 1
            let text = try String(contentsOf: url, encoding: .utf8)
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if line.drop(while: { $0 == " " }).hasPrefix("//") { continue }
                for pattern in Self.forbidden where line.contains(pattern) {
                    Issue.record("\(url.lastPathComponent):\(index + 1) uses \(pattern) outside UIText.swift")
                }
            }
        }
        #expect(scanned > 0, "\(tree): no sources found")
    }
}
