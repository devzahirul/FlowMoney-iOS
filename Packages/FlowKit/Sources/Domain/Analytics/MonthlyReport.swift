public import FlowCore
public import Foundation

public struct MonthlyReport: Sendable, Hashable {
    public let month: YearMonth
    public let flow: MonthFlow
    public let previousFlow: MonthFlow
    public let topCategories: [CategorySpend]
    public let largestExpense: LedgerTransaction?
    public let dailyAverage: Money
    public let transactionCount: Int

    public var spendingChange: Double? {
        CashFlow.change(from: previousFlow.expenses, to: flow.expenses)
    }

    public var incomeChange: Double? {
        CashFlow.change(from: previousFlow.income, to: flow.income)
    }

    public var netChange: Double? {
        CashFlow.change(from: previousFlow.net, to: flow.net)
    }

    /// The one-line headline at the top of the report.
    public var headline: String {
        guard let change = spendingChange else {
            return flow.expenses.isZero ? "No spending recorded yet this month." : "Your first month of tracking — nice start!"
        }
        let percent = Int((abs(change) * 100).rounded())
        if percent == 0 {
            return "You spent about the same as last month."
        }
        return change < 0 ? "You spent \(percent)% less than last month 🎉" : "You spent \(percent)% more than last month."
    }

    public static func make(for month: YearMonth, in snapshot: LedgerSnapshot, now: Date, calendar: Calendar) -> MonthlyReport {
        let flows = CashFlow.trailing(2, endingAt: month, in: snapshot, calendar: calendar)
        let interval = month.interval(in: calendar)
        let expenses = snapshot.transactions(in: interval).filter { $0.kind == .expense }
        let isCurrent = YearMonth(now, calendar: calendar) == month
        let elapsedDays = isCurrent ? calendar.component(.day, from: now) : month.dayCount(in: calendar)
        return MonthlyReport(
            month: month,
            flow: flows[1],
            previousFlow: flows[0],
            topCategories: SpendingBreakdown.byCategory(in: snapshot, interval: interval, limit: 5),
            largestExpense: expenses.max { $0.amount < $1.amount },
            dailyAverage: Money(minorUnits: flows[1].expenses.minorUnits / Int64(max(elapsedDays, 1))),
            transactionCount: snapshot.transactions(in: interval).count
        )
    }
}
