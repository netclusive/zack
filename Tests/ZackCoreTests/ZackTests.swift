import Testing

@testable import ZackCore

@Test func versionIsSemanticVersion() {
    let pattern = /^\d+\.\d+\.\d+(-[0-9A-Za-z.]+)?$/
    #expect(Zack.version.wholeMatch(of: pattern) != nil)
}
