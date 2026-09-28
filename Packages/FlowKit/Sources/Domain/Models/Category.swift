/// Stable identifier of a built-in category. Stored as text in Postgres so new categories never need a migration.
public struct CategoryID: RawRepresentable, Hashable, Codable, Sendable, ExpressibleByStringLiteral, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: String) {
        rawValue = value
    }

    public static func < (lhs: CategoryID, rhs: CategoryID) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum TransactionKind: String, Codable, Sendable, CaseIterable, Hashable {
    case expense
    case income
}

public struct Category: Identifiable, Hashable, Sendable {
    public let id: CategoryID
    public let name: String
    public let kind: TransactionKind

    public init(id: CategoryID, name: String, kind: TransactionKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

/// The built-in category set. Categories are app data, not user data: they ship with the binary,
/// never sync, and unknown IDs from a newer app version fall back to "Other" instead of crashing.
public enum CategoryCatalog {
    public static let expense: [Category] = [
        Category(id: .food, name: "Food & Drink", kind: .expense),
        Category(id: .groceries, name: "Groceries", kind: .expense),
        Category(id: .shopping, name: "Shopping", kind: .expense),
        Category(id: .transport, name: "Transport", kind: .expense),
        Category(id: .travel, name: "Travel", kind: .expense),
        Category(id: .bills, name: "Bills & Utilities", kind: .expense),
        Category(id: .housing, name: "Home", kind: .expense),
        Category(id: .entertainment, name: "Entertainment", kind: .expense),
        Category(id: .subscriptions, name: "Subscriptions", kind: .expense),
        Category(id: .health, name: "Health", kind: .expense),
        Category(id: .education, name: "Education", kind: .expense),
        Category(id: .personal, name: "Personal", kind: .expense),
        Category(id: .gifts, name: "Gifts", kind: .expense),
        Category(id: .otherExpense, name: "Other", kind: .expense),
    ]

    public static let income: [Category] = [
        Category(id: .salary, name: "Salary", kind: .income),
        Category(id: .freelance, name: "Freelance", kind: .income),
        Category(id: .investmentIncome, name: "Investments", kind: .income),
        Category(id: .giftsReceived, name: "Gifts", kind: .income),
        Category(id: .otherIncome, name: "Other", kind: .income),
    ]

    public static let all: [Category] = expense + income

    private static let byID: [CategoryID: Category] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    public static func categories(for kind: TransactionKind) -> [Category] {
        kind == .expense ? expense : income
    }

    public static func category(_ id: CategoryID) -> Category {
        byID[id] ?? Category(id: id, name: "Other", kind: .expense)
    }
}

public extension CategoryID {
    static let food: CategoryID = "food"
    static let groceries: CategoryID = "groceries"
    static let shopping: CategoryID = "shopping"
    static let transport: CategoryID = "transport"
    static let travel: CategoryID = "travel"
    static let bills: CategoryID = "bills"
    static let housing: CategoryID = "housing"
    static let entertainment: CategoryID = "entertainment"
    static let subscriptions: CategoryID = "subscriptions"
    static let health: CategoryID = "health"
    static let education: CategoryID = "education"
    static let personal: CategoryID = "personal"
    static let gifts: CategoryID = "gifts"
    static let otherExpense: CategoryID = "other"
    static let salary: CategoryID = "salary"
    static let freelance: CategoryID = "freelance"
    static let investmentIncome: CategoryID = "investment_income"
    static let giftsReceived: CategoryID = "gifts_received"
    static let otherIncome: CategoryID = "other_income"

    var category: Category {
        CategoryCatalog.category(self)
    }
}
