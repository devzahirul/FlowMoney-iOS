public import FlowCore
public import Foundation

public enum RecurrenceFrequency: String, Codable, Sendable, CaseIterable, Hashable {
    case weekly, monthly, quarterly, yearly

    public var title: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Quarterly"
        case .yearly: "Yearly"
        }
    }

    var step: (component: Calendar.Component, value: Int) {
        switch self {
        case .weekly: (.weekOfYear, 1)
        case .monthly: (.month, 1)
        case .quarterly: (.month, 3)
        case .yearly: (.year, 1)
        }
    }

    /// How many occurrences fall in a year — used to show a monthly-equivalent cost.
    public var perYear: Int {
        switch self {
        case .weekly: 52
        case .monthly: 12
        case .quarterly: 4
        case .yearly: 1
        }
    }
}

/// A repeating bill, subscription or paycheck.
public struct RecurringRule: LedgerRecord {
    public static let kind = RecordKind.recurringRule

    public let id: UUID
    public var name: String
    public var kind: TransactionKind
    public var amount: Money
    public var categoryID: CategoryID
    public var accountID: UUID
    public var frequency: RecurrenceFrequency
    /// The first due date. Later dates are computed from it (never chained), so Jan 31 → Feb 28 → Mar 31.
    public var startDate: Date
    /// Subscriptions appear in the Subscriptions tracker; other rules only under Recurring.
    public var isSubscription: Bool
    /// When on, due occurrences are posted as transactions automatically.
    public var autoPost: Bool
    public var isPaused: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(
        id: UUID = UUID(),
        name: String,
        kind: TransactionKind = .expense,
        amount: Money,
        categoryID: CategoryID,
        accountID: UUID,
        frequency: RecurrenceFrequency,
        startDate: Date,
        isSubscription: Bool = false,
        autoPost: Bool = true,
        isPaused: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.amount = amount
        self.categoryID = categoryID
        self.accountID = accountID
        self.frequency = frequency
        self.startDate = startDate
        self.isSubscription = isSubscription
        self.autoPost = autoPost
        self.isPaused = isPaused
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Cost normalised to one month (a $120/year plan is $10/month), for subscription totals.
    public var monthlyEquivalent: Money {
        Money(minorUnits: (amount.minorUnits * Int64(frequency.perYear)) / 12)
    }

    /// The n-th due date (n = 0 is `startDate`), computed from the start to avoid month-end drift.
    public func occurrence(_ index: Int, calendar: Calendar) -> Date? {
        let step = frequency.step
        return calendar.date(byAdding: step.component, value: step.value * index, to: startDate)
    }

    /// The first due date on or after the start of `date`'s day.
    public func nextOccurrence(onOrAfter date: Date, calendar: Calendar) -> Date? {
        firstIndex(onOrAfter: date, calendar: calendar).flatMap { occurrence($0, calendar: calendar) }
    }

    /// Due dates in `[from, through]`, capped at `limit` so a bad start date can't spin forever.
    public func occurrences(from: Date, through: Date, calendar: Calendar, limit: Int = 400) -> [Date] {
        guard var index = firstIndex(onOrAfter: from, calendar: calendar) else { return [] }
        var dates: [Date] = []
        while dates.count < limit, let date = occurrence(index, calendar: calendar), date <= through {
            dates.append(date)
            index += 1
        }
        return dates
    }

    /// Index of the first occurrence on or after the start of `date`'s day. Jumps close to the answer
    /// arithmetically and then walks a step or two — O(1) instead of O(number of past occurrences).
    private func firstIndex(onOrAfter date: Date, calendar: Calendar) -> Int? {
        let dayStart = calendar.startOfDay(for: date)
        guard startDate < dayStart else { return 0 }
        let step = frequency.step
        let elapsed = calendar.dateComponents([step.component], from: startDate, to: dayStart)
        var index = max(0, (elapsed.value(for: step.component) ?? 0) / step.value - 1)
        while let candidate = occurrence(index, calendar: calendar) {
            if candidate >= dayStart {
                return index
            }
            index += 1
        }
        return nil
    }

    /// The deterministic ID of the transaction posted for the occurrence on `date` (see `UUID(namespace:name:)`).
    public func postedTransactionID(for date: Date, calendar: Calendar) -> UUID {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let name = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return UUID(namespace: id, name: name)
    }
}
