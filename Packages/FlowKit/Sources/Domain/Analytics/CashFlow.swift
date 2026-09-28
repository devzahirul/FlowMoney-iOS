public import FlowCore
public import Foundation

public struct MonthFlow: Sendable, Hashable, Identifiable {
    public let month: YearMonth
    public let income: Money
    public let expenses: Money

    public var id: YearMonth {
        month
    }

    public var net: Money {
        income - expenses
    }

    /// Share of income kept, 0…1 (negative when spending exceeded income).
    public var savingsRate: Double {
        net.fraction(of: income)
    }

    public init(month: YearMonth, income: Money, expenses: Money) {
        self.month = month
        self.income = income
        self.expenses = expenses
    }
}

public enum CashFlow {
    /// Income and spending per month for the `count` months ending at `month`, oldest first. One pass.
    public static func trailing(
        _ count: Int,
        endingAt month: YearMonth,
        in snapshot: LedgerSnapshot,
        calendar: Calendar
    ) -> [MonthFlow] {
        let months = month.trailing(count)
        guard let first = months.first else { return [] }
        let range = DateInterval(start: first.firstDay(in: calendar), end: month.next.firstDay(in: calendar))
        var income: [YearMonth: Money] = [:]
        var expenses: [YearMonth: Money] = [:]
        for transaction in snapshot.transactions(in: range) {
            let key = YearMonth(transaction.date, calendar: calendar)
            switch transaction.kind {
            case .income: income[key, default: .zero] += transaction.amount
            case .expense: expenses[key, default: .zero] += transaction.amount
            }
        }
        return months.map { MonthFlow(month: $0, income: income[$0] ?? .zero, expenses: expenses[$0] ?? .zero) }
    }

    public static func month(_ month: YearMonth, in snapshot: LedgerSnapshot, calendar: Calendar) -> MonthFlow {
        trailing(1, endingAt: month, in: snapshot, calendar: calendar)[0]
    }

    /// Percentage change from `previous` to `current` (0.12 = +12%), `nil` when there's no baseline.
    public static func change(from previous: Money, to current: Money) -> Double? {
        guard previous.minorUnits != 0 else { return nil }
        return Double(current.minorUnits - previous.minorUnits) / Double(abs(previous.minorUnits))
    }
}
