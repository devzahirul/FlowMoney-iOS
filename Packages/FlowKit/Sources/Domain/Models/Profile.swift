public import Foundation

/// The signed-in user's settings that follow them across devices. `id` is the Supabase auth user ID.
public struct Profile: LedgerRecord {
    public static let kind = RecordKind.profile

    public let id: UUID
    public var displayName: String
    public var currencyCode: String
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID,
        displayName: String,
        currencyCode: String = "USD",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.currencyCode = currencyCode
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// "Alex" from "Alex Johnson", for the dashboard greeting.
    public var firstName: String {
        displayName.split(separator: " ").first.map(String.init) ?? displayName
    }

    /// "AJ" for avatar placeholders.
    public var initials: String {
        let letters = displayName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}
