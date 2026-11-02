import Foundation
import Testing

@testable import ZackDesktop

/// Pins the language of the package's interface texts for a suite or test.
struct UILanguageTrait: SuiteTrait, TestTrait, TestScoping {
    let locale: Locale
    var isRecursive: Bool { true }

    func provideScope(
        for test: Test, testCase: Test.Case?, performing function: @Sendable () async throws -> Void
    ) async throws {
        try await UIText.$locale.withValue(locale) { try await function() }
    }
}

extension Trait where Self == UILanguageTrait {
    static var germanUI: Self { Self(locale: Locale(identifier: "de")) }
    static var englishUI: Self { Self(locale: Locale(identifier: "en")) }
}
