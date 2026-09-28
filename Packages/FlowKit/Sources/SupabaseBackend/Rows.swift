import Domain
import FlowCore
import Foundation

// Wire formats for the Postgres tables. Explicit snake_case `CodingKeys` (not a key strategy) keep the
// mapping greppable and make a renamed column a compile-visible change. Domain types never see these.

struct ProfileRow: Codable, Equatable {
    let id: UUID
    let displayName: String
    let currencyCode: String
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, displayName = "display_name", currencyCode = "currency_code"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    /// Explicit, because synthesized `Codable` *omits* nil optionals — and an omitted `deleted_at` would
    /// mean "restore" never reaches the server. Every column is always sent, nulls included.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(currencyCode, forKey: .currencyCode)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    init(_ model: Profile) {
        id = model.id
        displayName = model.displayName
        currencyCode = model.currencyCode
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }

    var model: Profile {
        Profile(
            id: id,
            displayName: displayName,
            currencyCode: currencyCode,
            createdAt: createdAt,
            updatedAt: updatedAt,
            deletedAt: deletedAt
        )
    }
}

struct AccountRow: Codable, Equatable {
    let id: UUID
    let name: String
    let kind: String
    let institution: String
    let lastFour: String?
    let openingBalance: Int64
    let sortOrder: Int
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, kind, institution, lastFour = "last_four", openingBalance = "opening_balance", sortOrder = "sort_order"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    /// Explicit, because synthesized `Codable` *omits* nil optionals — and an omitted `deleted_at` would
    /// mean "restore" never reaches the server. Every column is always sent, nulls included.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(institution, forKey: .institution)
        try container.encode(lastFour, forKey: .lastFour)
        try container.encode(openingBalance, forKey: .openingBalance)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    init(_ model: Account) {
        id = model.id
        name = model.name
        kind = model.kind.rawValue
        institution = model.institution
        lastFour = model.lastFour
        openingBalance = model.openingBalance.minorUnits
        sortOrder = model.sortOrder
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }

    var model: Account {
        Account(
            id: id, name: name, kind: AccountKind(rawValue: kind) ?? .checking, institution: institution, lastFour: lastFour,
            openingBalance: Money(minorUnits: openingBalance), sortOrder: sortOrder,
            createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}

struct TransactionRow: Codable, Equatable {
    let id: UUID
    let accountID: UUID
    let kind: String
    let amount: Int64
    let categoryID: String
    let merchant: String
    let note: String
    let occurredAt: Date
    let recurringRuleID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountID = "account_id", kind, amount, categoryID = "category_id", merchant, note
        case occurredAt = "occurred_at", recurringRuleID = "recurring_rule_id"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    /// Explicit, because synthesized `Codable` *omits* nil optionals — and an omitted `deleted_at` would
    /// mean "restore" never reaches the server. Every column is always sent, nulls included.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(kind, forKey: .kind)
        try container.encode(amount, forKey: .amount)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(merchant, forKey: .merchant)
        try container.encode(note, forKey: .note)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encode(recurringRuleID, forKey: .recurringRuleID)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    init(_ model: LedgerTransaction) {
        id = model.id
        accountID = model.accountID
        kind = model.kind.rawValue
        amount = model.amount.minorUnits
        categoryID = model.categoryID.rawValue
        merchant = model.merchant
        note = model.note
        occurredAt = model.date
        recurringRuleID = model.recurringRuleID
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }

    var model: LedgerTransaction {
        LedgerTransaction(
            id: id, accountID: accountID, kind: TransactionKind(rawValue: kind) ?? .expense, amount: Money(minorUnits: amount),
            categoryID: CategoryID(rawValue: categoryID), merchant: merchant, note: note, date: occurredAt,
            recurringRuleID: recurringRuleID, createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}

struct BudgetRow: Codable, Equatable {
    let id: UUID
    let categoryID: String
    let limitAmount: Int64
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, categoryID = "category_id", limitAmount = "limit_amount"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    /// Explicit, because synthesized `Codable` *omits* nil optionals — and an omitted `deleted_at` would
    /// mean "restore" never reaches the server. Every column is always sent, nulls included.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(limitAmount, forKey: .limitAmount)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    init(_ model: Budget) {
        id = model.id
        categoryID = model.categoryID.rawValue
        limitAmount = model.limit.minorUnits
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }

    var model: Budget {
        Budget(
            id: id, categoryID: CategoryID(rawValue: categoryID), limit: Money(minorUnits: limitAmount),
            createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}

struct GoalRow: Codable, Equatable {
    let id: UUID
    let name: String
    let symbol: String
    let target: Int64
    let targetDate: Date?
    let monthlyContribution: Int64
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, symbol, target, targetDate = "target_date", monthlyContribution = "monthly_contribution"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    /// Explicit, because synthesized `Codable` *omits* nil optionals — and an omitted `deleted_at` would
    /// mean "restore" never reaches the server. Every column is always sent, nulls included.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(symbol, forKey: .symbol)
        try container.encode(target, forKey: .target)
        try container.encode(targetDate, forKey: .targetDate)
        try container.encode(monthlyContribution, forKey: .monthlyContribution)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    init(_ model: Goal) {
        id = model.id
        name = model.name
        symbol = model.symbol.rawValue
        target = model.target.minorUnits
        targetDate = model.targetDate
        monthlyContribution = model.monthlyContribution.minorUnits
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }

    var model: Goal {
        Goal(
            id: id, name: name, symbol: GoalSymbol(rawValue: symbol) ?? .other, target: Money(minorUnits: target),
            targetDate: targetDate, monthlyContribution: Money(minorUnits: monthlyContribution),
            createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}

struct ContributionRow: Codable, Equatable {
    let id: UUID
    let goalID: UUID
    let amount: Int64
    let contributedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, goalID = "goal_id", amount, contributedAt = "contributed_at"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    /// Explicit, because synthesized `Codable` *omits* nil optionals — and an omitted `deleted_at` would
    /// mean "restore" never reaches the server. Every column is always sent, nulls included.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(goalID, forKey: .goalID)
        try container.encode(amount, forKey: .amount)
        try container.encode(contributedAt, forKey: .contributedAt)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    init(_ model: GoalContribution) {
        id = model.id
        goalID = model.goalID
        amount = model.amount.minorUnits
        contributedAt = model.date
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }

    var model: GoalContribution {
        GoalContribution(
            id: id, goalID: goalID, amount: Money(minorUnits: amount), date: contributedAt,
            createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}

struct RecurringRuleRow: Codable, Equatable {
    let id: UUID
    let accountID: UUID
    let name: String
    let kind: String
    let amount: Int64
    let categoryID: String
    let frequency: String
    let startDate: Date
    let isSubscription: Bool
    let autoPost: Bool
    let isPaused: Bool
    let createdAt: Date
    let updatedAt: Date
    let deletedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, accountID = "account_id", name, kind, amount, categoryID = "category_id", frequency
        case startDate = "start_date", isSubscription = "is_subscription", autoPost = "auto_post", isPaused = "is_paused"
        case createdAt = "created_at", updatedAt = "updated_at", deletedAt = "deleted_at"
    }

    /// Explicit, because synthesized `Codable` *omits* nil optionals — and an omitted `deleted_at` would
    /// mean "restore" never reaches the server. Every column is always sent, nulls included.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(accountID, forKey: .accountID)
        try container.encode(name, forKey: .name)
        try container.encode(kind, forKey: .kind)
        try container.encode(amount, forKey: .amount)
        try container.encode(categoryID, forKey: .categoryID)
        try container.encode(frequency, forKey: .frequency)
        try container.encode(startDate, forKey: .startDate)
        try container.encode(isSubscription, forKey: .isSubscription)
        try container.encode(autoPost, forKey: .autoPost)
        try container.encode(isPaused, forKey: .isPaused)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(deletedAt, forKey: .deletedAt)
    }

    init(_ model: RecurringRule) {
        id = model.id
        accountID = model.accountID
        name = model.name
        kind = model.kind.rawValue
        amount = model.amount.minorUnits
        categoryID = model.categoryID.rawValue
        frequency = model.frequency.rawValue
        startDate = model.startDate
        isSubscription = model.isSubscription
        autoPost = model.autoPost
        isPaused = model.isPaused
        createdAt = model.createdAt
        updatedAt = model.updatedAt
        deletedAt = model.deletedAt
    }

    var model: RecurringRule {
        RecurringRule(
            id: id, name: name, kind: TransactionKind(rawValue: kind) ?? .expense, amount: Money(minorUnits: amount),
            categoryID: CategoryID(rawValue: categoryID), accountID: accountID,
            frequency: RecurrenceFrequency(rawValue: frequency) ?? .monthly, startDate: startDate,
            isSubscription: isSubscription, autoPost: autoPost, isPaused: isPaused,
            createdAt: createdAt, updatedAt: updatedAt, deletedAt: deletedAt
        )
    }
}
