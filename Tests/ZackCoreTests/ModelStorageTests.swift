import Testing

@testable import ZackCore

@Test func modelsLiveInApplicationSupport() throws {
    let url = try ModelStorage.directory(createIfNeeded: false)
    #expect(url.path.hasSuffix("/Library/Application Support/Zack/Models"))
    #expect(!url.path.contains("/Documents/"))
}
