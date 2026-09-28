public import Foundation

/// Project URL + publishable key, read from Info.plist (which gets them from the git-ignored
/// `Config/Supabase.local.xcconfig`). When either is missing the app runs in demo-only mode.
public struct SupabaseConfiguration: Sendable, Equatable {
    public let url: URL
    /// The *publishable* (anon) key — designed to ship in apps; Row Level Security protects the data.
    public let publishableKey: String
    /// FlowMoney's tables live in their own Postgres schema so the project can be shared with other apps.
    public static let schema = "flowmoney"

    public init(url: URL, publishableKey: String) {
        self.url = url
        self.publishableKey = publishableKey
    }

    public init?(infoDictionary: [String: Any]?) {
        guard let host = (infoDictionary?["FlowMoneySupabaseHost"] as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (infoDictionary?["FlowMoneySupabaseKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              !host.isEmpty, !key.isEmpty, !host.contains("$("),
              let url = URL(string: "https://\(host)") else { return nil }
        self.init(url: url, publishableKey: key)
    }

    public var host: String {
        url.host() ?? url.absoluteString
    }
}
