public import FlowCore
public import Foundation

/// A single income or expense. Named `LedgerTransaction` so it never collides with `SwiftUI.Transaction`.
public struct LedgerTransaction: LedgerRecord {
    public static let kind = RecordKind.transaction

    public let id: UUID
    public var accountID: UUID
    public var kind: TransactionKind
    /// Always positive; the sign comes from `kind`. Keeps "amount > 0" a simple database check constraint.
    public var amount: Money
    public var categoryID: CategoryID
    public var merchant: String
    public var note: String
    public var date: Date
    /// Set when the row was auto-posted by a recurring rule.
    public var recurringRuleID: UUID?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        kind: TransactionKind,
        amount: Money,
        categoryID: CategoryID,
        merchant: String,
        note: String = "",
        date: Date,
        recurringRuleID: UUID? = nil,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.kind = kind
        self.amount = amount
        self.categoryID = categoryID
        self.merchant = merchant
        self.note = note
        self.date = date
        self.recurringRuleID = recurringRuleID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Positive for income, negative for spending — what gets added to an account balance.
    public var signedAmount: Money {
        kind == .income ? amount : -amount
    }

    public var category: Category {
        categoryID.category
    }

    /// The name shown in lists: the merchant, or the category when the merchant was left empty.
    public var displayTitle: String {
        merchant.isEmpty ? category.name : merchant
    }
}
