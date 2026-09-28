public import FlowCore
public import Foundation

public enum GoalSymbol: String, Codable, Sendable, CaseIterable, Hashable {
    case vacation, car, home, emergency, education, wedding, gadget, other
}

public struct Goal: LedgerRecord {
    public static let kind = RecordKind.goal

    public let id: UUID
    public var name: String
    public var symbol: GoalSymbol
    public var target: Money
    public var targetDate: Date?
    /// The planned monthly saving, used to project whether the goal is on track.
    public var monthlyContribution: Money
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        symbol: GoalSymbol = .other,
        target: Money,
        targetDate: Date? = nil,
        monthlyContribution: Money = .zero,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.target = target
        self.targetDate = targetDate
        self.monthlyContribution = monthlyContribution
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// Money added to (or withdrawn from) a goal. Stored as rows rather than a `saved` counter on the goal,
/// so two devices adding money at the same time both count — a counter would lose one of the writes.
public struct GoalContribution: LedgerRecord {
    public static let kind = RecordKind.goalContribution

    public let id: UUID
    public var goalID: UUID
    /// Negative for a withdrawal.
    public var amount: Money
    public var date: Date
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        goalID: UUID,
        amount: Money,
        date: Date,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.goalID = goalID
        self.amount = amount
        self.date = date
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}
