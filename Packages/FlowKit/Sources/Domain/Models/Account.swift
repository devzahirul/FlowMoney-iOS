public import FlowCore
public import Foundation

public enum AccountKind: String, Codable, Sendable, CaseIterable, Hashable {
    case checking
    case savings
    case cash
    case investment
    case property
    case creditCard = "credit_card"
    case loan

    /// Liabilities carry a negative balance (money owed) and are summed separately in Net Worth.
    public var isLiability: Bool {
        self == .creditCard || self == .loan
    }

    public var title: String {
        switch self {
        case .checking: "Checking"
        case .savings: "Savings"
        case .cash: "Cash"
        case .investment: "Investment"
        case .property: "Property"
        case .creditCard: "Credit Card"
        case .loan: "Loan"
        }
    }
}

public struct Account: LedgerRecord {
    public static let kind = RecordKind.account

    public let id: UUID
    public var name: String
    public var kind: AccountKind
    public var institution: String
    /// Last four digits for display only ("•••• 4821"). Full numbers are never stored.
    public var lastFour: String?
    /// Balance before the first tracked transaction. Negative for debts.
    public var openingBalance: Money
    public var sortOrder: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: AccountKind,
        institution: String = "",
        lastFour: String? = nil,
        openingBalance: Money = .zero,
        sortOrder: Int = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.institution = institution
        self.lastFour = lastFour
        self.openingBalance = openingBalance
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
