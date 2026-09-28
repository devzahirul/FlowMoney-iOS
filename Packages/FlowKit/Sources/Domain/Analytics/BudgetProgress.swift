public import FlowCore
public import Foundation

public struct BudgetStatus: Identifiable, Sendable, Hashable {
    public enum Level: Sendable, Hashable, Comparable {
        case onTrack
        /// 80% or more used.
        case nearLimit
        case over
    }

    public let budget: Budget
    public let spent: Money
    /// Spend extrapolated to month end at the current daily pace.
    public let projected: Money

    public var id: UUID {
        budget.id
    }

    public var remaining: Money {
        budget.limit - spent
    }

    public var fraction: Double {
        spent.fraction(of: budget.limit)
    }

    public var level: Level {
        if spent > budget.limit {
            return .over
        }
        if fraction >= BudgetProgress.warningThreshold {
            return .nearLimit
        }
        return .onTrack
    }

    /// True when the current pace will blow the budget before month end, even if it isn't over yet.
    public var isProjectedOver: Bool {
        projected > budget.limit
    }
}

public struct BudgetSummary: Sendable, Hashable {
    public let month: YearMonth
    public let statuses: [BudgetStatus]

    public var totalLimit: Money {
        statuses.sum(\.budget.limit)
    }

    public var totalSpent: Money {
        statuses.sum(\.spent)
    }

    public var fraction: Double {
        totalSpent.fraction(of: totalLimit)
    }
}

public enum BudgetProgress {
    public static let warningThreshold = 0.8

    /// Spending per budgeted category for `month`, projected to month end when `month` is the current one.
    public static func summary(
        for snapshot: LedgerSnapshot,
        month: YearMonth,
        now: Date,
        calendar: Calendar
    ) -> BudgetSummary {
        var spentByCategory: [CategoryID: Money] = [:]
        for transaction in snapshot.transactions(in: month, calendar: calendar) where transaction.kind == .expense {
            spentByCategory[transaction.categoryID, default: .zero] += transaction.amount
        }
        let pace = paceMultiplier(month: month, now: now, calendar: calendar)
        let statuses = snapshot.budgets.map { budget in
            let spent = spentByCategory[budget.categoryID] ?? .zero
            return BudgetStatus(
                budget: budget,
                spent: spent,
                projected: Money(minorUnits: Int64((Double(spent.minorUnits) * pace).rounded()))
            )
        }
        return BudgetSummary(month: month, statuses: statuses)
    }

    /// Days in month ÷ days elapsed for the current month; 1 for past months (already complete).
    static func paceMultiplier(month: YearMonth, now: Date, calendar: Calendar) -> Double {
        guard YearMonth(now, calendar: calendar) == month else { return 1 }
        let day = calendar.component(.day, from: now)
        return Double(month.dayCount(in: calendar)) / Double(max(day, 1))
    }

    /// Daily spending for one category in `month`, for the budget detail chart.
    public static func dailySpending(
        category: CategoryID,
        in snapshot: LedgerSnapshot,
        month: YearMonth,
        calendar: Calendar
    ) -> [DatedAmount] {
        var byDay: [Date: Money] = [:]
        for transaction in snapshot.transactions(in: month, calendar: calendar)
            where transaction.kind == .expense && transaction.categoryID == category {
            byDay[calendar.startOfDay(for: transaction.date), default: .zero] += transaction.amount
        }
        return byDay.map { DatedAmount(date: $0.key, amount: $0.value) }.sorted { $0.date < $1.date }
    }
}

public struct DatedAmount: Sendable, Hashable, Identifiable {
    public let date: Date
    public let amount: Money
    public var id: Date {
        date
    }

    public init(date: Date, amount: Money) {
        self.date = date
        self.amount = amount
    }
}
