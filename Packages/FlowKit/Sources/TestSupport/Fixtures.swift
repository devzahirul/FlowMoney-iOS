public import Domain
public import FlowCore
public import Foundation

/// Tests run in a fixed Gregorian/UTC calendar so results never depend on the machine's locale or time zone.
public enum TestCalendar {
    public static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.firstWeekday = 2
        return calendar
    }()

    // swiftlint:disable:next function_default_parameter_at_end
    public static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        // swiftlint:disable:next force_unwrapping
        utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }
}

public extension Money {
    /// `.dollars(12.5)` → 1250 minor units. Test-only readability helper.
    static func dollars(_ value: Double) -> Money {
        Money(minorUnits: Int64((value * 100).rounded()))
    }
}

public enum Fixture {
    public static let userID = UUID(uuidString: "11111111-1111-4111-8111-111111111111") ?? UUID()
    public static let checkingID = UUID(uuidString: "22222222-2222-4222-8222-222222222222") ?? UUID()
    public static let epoch = TestCalendar.date(2026, 1, 1)

    public static func profile(name: String = "Alex Johnson", currency: String = "USD") -> Profile {
        Profile(id: userID, displayName: name, currencyCode: currency, createdAt: epoch, updatedAt: epoch)
    }

    public static func account(
        id: UUID = checkingID,
        name: String = "Checking",
        kind: AccountKind = .checking,
        opening: Money = .zero,
        updatedAt: Date = epoch
    ) -> Account {
        Account(id: id, name: name, kind: kind, openingBalance: opening, createdAt: epoch, updatedAt: updatedAt)
    }

    public static func expense(
        _ amount: Money,
        _ category: CategoryID = .food,
        on date: Date,
        merchant: String = "Store",
        note: String = "",
        account: UUID = checkingID,
        id: UUID = UUID()
    ) -> LedgerTransaction {
        LedgerTransaction(
            id: id, accountID: account, kind: .expense, amount: amount, categoryID: category,
            merchant: merchant, note: note, date: date, createdAt: date, updatedAt: date
        )
    }

    public static func income(
        _ amount: Money,
        _ category: CategoryID = .salary,
        on date: Date,
        merchant: String = "Employer",
        account: UUID = checkingID,
        id: UUID = UUID()
    ) -> LedgerTransaction {
        LedgerTransaction(
            id: id, accountID: account, kind: .income, amount: amount, categoryID: category,
            merchant: merchant, date: date, createdAt: date, updatedAt: date
        )
    }

    public static func budget(_ category: CategoryID, limit: Money, id: UUID = UUID()) -> Budget {
        Budget(id: id, categoryID: category, limit: limit, createdAt: epoch, updatedAt: epoch)
    }

    public static func goal(
        name: String = "Trip",
        target: Money,
        targetDate: Date? = nil,
        monthly: Money = .zero,
        id: UUID = UUID()
    ) -> Goal {
        Goal(id: id, name: name, target: target, targetDate: targetDate, monthlyContribution: monthly, createdAt: epoch, updatedAt: epoch)
    }

    public static func contribution(_ amount: Money, to goalID: UUID, on date: Date) -> GoalContribution {
        GoalContribution(goalID: goalID, amount: amount, date: date, createdAt: date, updatedAt: date)
    }

    public static func rule(
        name: String = "Netflix",
        amount: Money = .dollars(15.99),
        frequency: RecurrenceFrequency = .monthly,
        start: Date,
        subscription: Bool = true,
        createdAt: Date? = nil,
        id: UUID = UUID()
    ) -> RecurringRule {
        RecurringRule(
            id: id, name: name, amount: amount, categoryID: .subscriptions, accountID: checkingID,
            frequency: frequency, startDate: start, isSubscription: subscription,
            createdAt: createdAt ?? start, updatedAt: createdAt ?? start
        )
    }

    public static func snapshot(
        accounts: [Account] = [account()],
        transactions: [LedgerTransaction] = [],
        budgets: [Budget] = [],
        goals: [Goal] = [],
        contributions: [GoalContribution] = [],
        rules: [RecurringRule] = []
    ) -> LedgerSnapshot {
        LedgerSnapshot(
            profile: profile(),
            accounts: accounts,
            transactions: transactions,
            budgets: budgets,
            goals: goals,
            contributions: contributions,
            recurringRules: rules
        )
    }
}
