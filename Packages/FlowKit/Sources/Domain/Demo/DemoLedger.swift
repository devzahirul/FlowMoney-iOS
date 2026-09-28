public import Foundation
import FlowCore

/// A realistic, *deterministic* ledger (seeded RNG, dates relative to `now`) used for demo mode,
/// App Review, SwiftUI previews, UI tests and performance benchmarks. Same inputs → identical data.
public enum DemoLedger {
    // swiftlint:disable:next force_unwrapping
    public static let userID = UUID(uuidString: "D3E0D3E0-0000-4000-8000-00000000F10E")!

    public struct Content: Sendable {
        public var profile: Profile
        public var accounts: [Account]
        public var transactions: [LedgerTransaction]
        public var budgets: [Budget]
        public var goals: [Goal]
        public var contributions: [GoalContribution]
        public var recurringRules: [RecurringRule]

        public var snapshot: LedgerSnapshot {
            LedgerSnapshot(
                profile: profile,
                accounts: accounts,
                transactions: transactions,
                budgets: budgets,
                goals: goals,
                contributions: contributions,
                recurringRules: recurringRules,
                revision: 1
            )
        }
    }

    /// - Parameter extraTransactionsPerDay: scales volume for performance tests (0 = normal demo).
    public static func make(now: Date, calendar: Calendar, historyMonths: Int = 5, extraTransactionsPerDay: Int = 0) -> Content {
        var rng = SeededGenerator(seed: 0xF10E_2026)
        let historyStart = YearMonth(now, calendar: calendar).adding(months: -historyMonths).firstDay(in: calendar)

        let checking = Account(
            id: id(1), name: "Chase Checking", kind: .checking, institution: "Chase", lastFour: "4821",
            openingBalance: Money(minorUnits: 612_000), sortOrder: 0, createdAt: historyStart, updatedAt: historyStart
        )
        let savings = Account(
            id: id(2), name: "Savings Account", kind: .savings, institution: "Ally",
            openingBalance: Money(minorUnits: 1_050_000), sortOrder: 1, createdAt: historyStart, updatedAt: historyStart
        )
        let investment = Account(
            id: id(3), name: "Investment", kind: .investment, institution: "Vanguard",
            openingBalance: Money(minorUnits: 422_030), sortOrder: 2, createdAt: historyStart, updatedAt: historyStart
        )
        let credit = Account(
            id: id(4), name: "Credit Card", kind: .creditCard, institution: "Amex", lastFour: "1007",
            openingBalance: Money(minorUnits: -48000), sortOrder: 3, createdAt: historyStart, updatedAt: historyStart
        )
        let accounts = [checking, savings, investment, credit]

        let rules = recurringRules(checking: checking.id, credit: credit.id, start: historyStart, calendar: calendar)
        var transactions = RecurringPoster.dueTransactions(rules: rules, existingIDs: [], now: now, calendar: calendar)
            .map { transaction in
                var copy = transaction
                copy.createdAt = transaction.date
                copy.updatedAt = transaction.date
                return copy
            }

        var day = historyStart
        var serial = 0
        while day <= now {
            for template in dailyTemplates {
                guard rng.nextDouble() < template.probability else { continue }
                serial += 1
                transactions.append(template.make(
                    id: id(10000 + serial),
                    day: day,
                    account: template.useCredit && rng.nextDouble() < 0.5 ? credit.id : checking.id,
                    rng: &rng,
                    calendar: calendar,
                    now: now
                ))
            }
            for _ in 0 ..< extraTransactionsPerDay {
                serial += 1
                let template = dailyTemplates[Int(rng.next() % UInt64(dailyTemplates.count))]
                transactions.append(template.make(
                    id: id(10000 + serial), day: day, account: checking.id, rng: &rng, calendar: calendar, now: now
                ))
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let (goals, contributions) = goalsAndContributions(now: now, start: historyStart, calendar: calendar)
        let budgets: [Budget] = [
            (CategoryID.food, 50000), (.shopping, 40000), (.transport, 20000), (.entertainment, 15000), (.bills, 60000),
        ].map { pair in
            Budget(
                id: Budget.id(for: pair.0, owner: userID),
                categoryID: pair.0,
                limit: Money(minorUnits: pair.1),
                createdAt: historyStart,
                updatedAt: historyStart
            )
        }

        return Content(
            profile: Profile(
                id: userID,
                displayName: "Alex Johnson",
                currencyCode: "USD",
                createdAt: historyStart,
                updatedAt: historyStart
            ),
            accounts: accounts,
            transactions: transactions,
            budgets: budgets,
            goals: goals,
            contributions: contributions,
            recurringRules: rules
        )
    }

    // MARK: - Building blocks

    static func id(_ value: Int) -> UUID {
        UUID(namespace: userID, name: "demo-\(value)")
    }

    private static func recurringRules(checking: UUID, credit: UUID, start: Date, calendar: Calendar) -> [RecurringRule] {
        // swiftlint:disable:next large_tuple
        let specs: [(String, TransactionKind, Int64, CategoryID, UUID, RecurrenceFrequency, Int, Bool)] = [
            ("Salary", .income, 320_000, .salary, checking, .monthly, 1, false),
            ("Rent", .expense, 120_000, .housing, checking, .monthly, 1, false),
            ("Phone Bill", .expense, 8000, .bills, checking, .monthly, 12, false),
            ("Electricity", .expense, 6450, .bills, checking, .monthly, 18, false),
            ("Gym Membership", .expense, 2999, .health, credit, .monthly, 8, true),
            ("Netflix", .expense, 1599, .subscriptions, credit, .monthly, 3, true),
            ("Spotify", .expense, 1099, .subscriptions, credit, .monthly, 2, true),
            ("ChatGPT Plus", .expense, 2000, .subscriptions, credit, .monthly, 5, true),
            ("YouTube Premium", .expense, 1399, .subscriptions, credit, .monthly, 20, true),
            ("iCloud+", .expense, 999, .subscriptions, credit, .monthly, 24, true),
            ("Figma", .expense, 1200, .subscriptions, credit, .monthly, 27, true),
        ]
        return specs.enumerated().map { index, spec in
            let startDate = calendar.date(byAdding: .day, value: spec.6 - 1, to: start) ?? start
            return RecurringRule(
                id: id(300 + index),
                name: spec.0,
                kind: spec.1,
                amount: Money(minorUnits: spec.2),
                categoryID: spec.3,
                accountID: spec.4,
                frequency: spec.5,
                startDate: startDate,
                isSubscription: spec.7,
                autoPost: true,
                createdAt: start,
                updatedAt: start
            )
        }
    }

    private static func goalsAndContributions(now: Date, start: Date, calendar: Calendar) -> ([Goal], [GoalContribution]) {
        let inMonths = { (months: Int) in calendar.date(byAdding: .month, value: months, to: now) }
        let goals = [
            Goal(
                id: id(600), name: "Vacation in Japan", symbol: .vacation, target: Money(minorUnits: 500_000),
                targetDate: inMonths(10), monthlyContribution: Money(minorUnits: 30000), createdAt: start, updatedAt: start
            ),
            Goal(
                id: id(601), name: "New Car", symbol: .car, target: Money(minorUnits: 2_500_000),
                targetDate: inMonths(30), monthlyContribution: Money(minorUnits: 40000), createdAt: start, updatedAt: start
            ),
            Goal(
                id: id(602), name: "Emergency Fund", symbol: .emergency, target: Money(minorUnits: 1_000_000),
                targetDate: inMonths(8), monthlyContribution: Money(minorUnits: 50000), createdAt: start, updatedAt: start
            ),
        ]
        let seeds: [(goal: Int, amounts: [Int64])] = [
            (0, [120_000, 30000, 30000, 30000, 30000]),
            (1, [600_000, 40000, 40000, 40000, 40000, 40000]),
            (2, [400_000, 50000, 50000, 50000, 50000, 50000]),
        ]
        var contributions: [GoalContribution] = []
        for seed in seeds {
            for (offset, amount) in seed.amounts.enumerated() {
                let date = calendar.date(byAdding: .month, value: offset, to: start).map { min($0, now) } ?? start
                contributions.append(GoalContribution(
                    id: id(700 + seed.goal * 20 + offset),
                    goalID: goals[seed.goal].id,
                    amount: Money(minorUnits: amount),
                    date: date,
                    createdAt: date,
                    updatedAt: date
                ))
            }
        }
        return (goals, contributions)
    }

    private struct Template {
        let merchants: [String]
        let category: CategoryID
        let kind: TransactionKind
        let range: ClosedRange<Int64>
        let probability: Double
        var useCredit = false

        // swiftlint:disable:next function_parameter_count
        func make(id: UUID, day: Date, account: UUID, rng: inout SeededGenerator, calendar: Calendar, now: Date) -> LedgerTransaction {
            let hour = Int(rng.next() % 13) + 8
            let minute = Int(rng.next() % 60)
            var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
            if date > now {
                date = now.addingTimeInterval(-60)
            }
            let span = UInt64(range.upperBound - range.lowerBound + 1)
            let amount = range.lowerBound + Int64(rng.next() % span)
            return LedgerTransaction(
                id: id,
                accountID: account,
                kind: kind,
                amount: Money(minorUnits: amount),
                categoryID: category,
                merchant: merchants[Int(rng.next() % UInt64(merchants.count))],
                date: date,
                createdAt: date,
                updatedAt: date
            )
        }
    }

    private static let dailyTemplates: [Template] = [
        Template(
            merchants: ["Starbucks", "Blue Bottle Coffee", "Dunkin'"],
            category: .food,
            kind: .expense,
            range: 420 ... 780,
            probability: 0.55
        ),
        Template(
            merchants: ["Chipotle", "Sweetgreen", "Shake Shack", "Joe's Pizza"],
            category: .food,
            kind: .expense,
            range: 1100 ... 3200,
            probability: 0.3,
            useCredit: true
        ),
        Template(
            merchants: ["Whole Foods", "Trader Joe's", "Safeway"],
            category: .groceries,
            kind: .expense,
            range: 3500 ... 12000,
            probability: 0.2
        ),
        Template(merchants: ["Uber", "Lyft", "Shell"], category: .transport, kind: .expense, range: 900 ... 3200, probability: 0.18),
        Template(
            merchants: ["Amazon", "Target", "Uniqlo", "Apple Store"],
            category: .shopping,
            kind: .expense,
            range: 1500 ... 9800,
            probability: 0.1,
            useCredit: true
        ),
        Template(
            merchants: ["AMC Theatres", "Steam", "Ticketmaster"],
            category: .entertainment,
            kind: .expense,
            range: 1200 ... 6500,
            probability: 0.05,
            useCredit: true
        ),
        Template(merchants: ["CVS Pharmacy", "Walgreens"], category: .health, kind: .expense, range: 800 ... 4500, probability: 0.04),
        Template(
            merchants: ["Upwork Client", "Design Project"],
            category: .freelance,
            kind: .income,
            range: 25000 ... 90000,
            probability: 0.035
        ),
    ]
}

/// SplitMix64 — tiny, fast, and deterministic across platforms (unlike `SystemRandomNumberGenerator`).
public struct SeededGenerator: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }

    mutating func nextDouble() -> Double {
        Double(next() >> 11) / Double(1 << 53)
    }
}
