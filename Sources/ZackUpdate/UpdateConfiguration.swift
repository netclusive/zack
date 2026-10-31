import Foundation

/// Feed and signing key of an official build; nil when either is missing or malformed, so the updater stays off.
public struct UpdateConfiguration: Equatable, Sendable {
    public let feedURL: URL
    public let publicKey: String

    public init?(feedURL: String?, publicKey: String?) {
        guard let feed = feedURL?.trimmingCharacters(in: .whitespacesAndNewlines),
            let key = publicKey?.trimmingCharacters(in: .whitespacesAndNewlines),
            let url = URL(string: feed), let scheme = url.scheme?.lowercased(),
            let host = url.host(), !host.isEmpty,
            scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost"].contains(host.lowercased())),
            Data(base64Encoded: key)?.count == 32
        else { return nil }
        self.feedURL = url
        self.publicKey = key
    }

    /// Reads `SUFeedURL` and `SUPublicEDKey` from the bundle's Info dictionary.
    public init?(bundle: Bundle) {
        self.init(
            feedURL: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String)
    }
}
