import Foundation
import Testing

@testable import ZackUpdate

struct UpdateConfigurationTests {
    let key = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="  // 32 zero bytes, fake

    @Test func githubFeedWithKeyEnablesUpdates() {
        let config = UpdateConfiguration(
            feedURL: "https://github.com/netclusive/zack/releases/latest/download/appcast.xml", publicKey: key)
        #expect(config?.feedURL.host() == "github.com")
    }

    @Test func emptyValuesDisableUpdates() {
        #expect(UpdateConfiguration(feedURL: "", publicKey: key) == nil)
        #expect(UpdateConfiguration(feedURL: nil, publicKey: nil) == nil)
    }

    @Test func truncatedFeedURLDisablesUpdates() {
        #expect(UpdateConfiguration(feedURL: "https:", publicKey: key) == nil)
    }

    @Test func placeholderKeyDisablesUpdates() {
        #expect(UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: "CHANGEME") == nil)
        #expect(
            UpdateConfiguration(feedURL: "https://example.com/appcast.xml", publicKey: String(key.dropLast(4))) == nil)
    }

    @Test func plainHTTPOnlyForTheLocalTestFeed() {
        #expect(UpdateConfiguration(feedURL: "http://127.0.0.1:8000/appcast.xml", publicKey: key) != nil)
        #expect(UpdateConfiguration(feedURL: "http://example.com/appcast.xml", publicKey: key) == nil)
    }

    /// Plain HTTP is decided by the parsed host, not by a text prefix; user info and lookalike hosts do not count.
    @Test func loopbackLookalikesDisableUpdates() {
        #expect(UpdateConfiguration(feedURL: "http://127.0.0.1@example.com", publicKey: key) == nil)
        #expect(UpdateConfiguration(feedURL: "http://127.0.0.1.example.com", publicKey: key) == nil)
        #expect(UpdateConfiguration(feedURL: "https://", publicKey: key) == nil)
    }

    @Test func surroundingWhitespaceIsIgnored() {
        #expect(UpdateConfiguration(feedURL: " https://example.com/appcast.xml\n", publicKey: " \(key) ") != nil)
    }
}
