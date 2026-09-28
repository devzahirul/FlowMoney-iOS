public import FlowCore
public import Foundation

public enum EmailAddress {
    /// Pragmatic check (something@something.tld). The server is the real validator; this only
    /// stops obvious typos before a network round-trip.
    public static func isValid(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 254 else { return false }
        return trimmed.wholeMatch(of: #/[^\s@]+@[^\s@]+\.[^\s@]{2,}/#) != nil
    }
}

public struct PasswordRule: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let isSatisfied: Bool
}

/// The sign-up checklist (screen 3). Mirrors the minimum configured in Supabase Auth.
public enum PasswordPolicy {
    public static let minimumLength = 8

    public static func rules(for password: String) -> [PasswordRule] {
        [
            PasswordRule(id: "length", title: "At least \(minimumLength) characters", isSatisfied: password.count >= minimumLength),
            PasswordRule(id: "number", title: "One number", isSatisfied: password.contains(where: \.isNumber)),
            PasswordRule(
                id: "special",
                title: "One special character",
                isSatisfied: password.contains { !$0.isLetter && !$0.isNumber && !$0.isWhitespace }
            ),
        ]
    }

    public static func isValid(_ password: String) -> Bool {
        rules(for: password).allSatisfy(\.isSatisfied)
    }
}

/// Validated input for the Add Expense / Add Income screens.
public struct TransactionDraft: Sendable, Hashable {
    public var kind: TransactionKind
    public var amount: Money?
    public var categoryID: CategoryID?
    public var accountID: UUID?
    public var merchant: String
    public var note: String
    public var date: Date

    public init(
        kind: TransactionKind,
        amount: Money? = nil,
        categoryID: CategoryID? = nil,
        accountID: UUID? = nil,
        merchant: String = "",
        note: String = "",
        date: Date
    ) {
        self.kind = kind
        self.amount = amount
        self.categoryID = categoryID
        self.accountID = accountID
        self.merchant = merchant
        self.note = note
        self.date = date
    }

    public init(editing transaction: LedgerTransaction) {
        self.init(
            kind: transaction.kind,
            amount: transaction.amount,
            categoryID: transaction.categoryID,
            accountID: transaction.accountID,
            merchant: transaction.merchant,
            note: transaction.note,
            date: transaction.date
        )
    }

    public enum Problem: Error, Equatable, Sendable {
        case missingAmount, missingCategory, missingAccount, amountTooLarge
    }

    /// One billion in minor units — anything above is a typo, and it keeps sums far from `Int64` overflow.
    public static let maximumAmount = Money(minorUnits: 100_000_000_000)

    public var problem: Problem? {
        guard let amount, amount.minorUnits > 0 else { return .missingAmount }
        guard amount <= Self.maximumAmount else { return .amountTooLarge }
        guard categoryID != nil else { return .missingCategory }
        guard accountID != nil else { return .missingAccount }
        return nil
    }

    public var isValid: Bool {
        problem == nil
    }

    /// Builds the record to save; `existing` keeps the ID and creation date when editing.
    public func makeTransaction(existing: LedgerTransaction? = nil, now: Date) throws(Problem) -> LedgerTransaction {
        if let problem {
            throw problem
        }
        guard let amount, let categoryID, let accountID else { throw .missingAmount }
        return LedgerTransaction(
            id: existing?.id ?? UUID(),
            accountID: accountID,
            kind: kind,
            amount: amount,
            categoryID: categoryID,
            merchant: merchant.trimmingCharacters(in: .whitespacesAndNewlines),
            note: note.trimmingCharacters(in: .whitespacesAndNewlines),
            date: date,
            recurringRuleID: existing?.recurringRuleID,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
    }
}
