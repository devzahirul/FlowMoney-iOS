public import FlowCore
public import Foundation

/// A monthly spending limit for one category. At most one live budget per category (enforced by a
/// partial unique index server-side and by `BudgetEditor` client-side).
public struct Budget: LedgerRecord {
    public static let kind = RecordKind.budget

    public let id: UUID
    public var categoryID: CategoryID
    public var limit: Money
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        categoryID: CategoryID,
        limit: Money,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.categoryID = categoryID
        self.limit = limit
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// The ID a budget for `category` always has for this user. Two offline devices creating a "Food"
    /// budget produce the *same* row, so the server upsert merges them instead of hitting the
    /// one-budget-per-category unique index and wedging sync.
    public static func id(for category: CategoryID, owner: UUID) -> UUID {
        UUID(namespace: owner, name: "budget:\(category.rawValue)")
    }
}
