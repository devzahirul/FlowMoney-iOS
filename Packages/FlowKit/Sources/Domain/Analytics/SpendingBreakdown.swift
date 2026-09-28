public import FlowCore
public import Foundation

public struct CategorySpend: Sendable, Hashable, Identifiable {
    public let categoryID: CategoryID
    public let amount: Money
    /// Share of the period's total, 0…1.
    public let share: Double
    public let transactionCount: Int

    public var id: CategoryID {
        categoryID
    }

    public var category: Category {
        categoryID.category
    }
}

public enum AnalyticsPeriod: String, CaseIterable, Sendable, Hashable, Identifiable {
    case week, month, year

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        }
    }

    /// The period containing `now`, e.g. this calendar week.
    public func interval(containing now: Date, calendar: Calendar) -> DateInterval {
        let component: Calendar.Component = switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        return calendar.dateInterval(of: component, for: now) ?? DateInterval(start: now, duration: 0)
    }
}

public enum SpendingBreakdown {
    /// Spending per category in `interval`, largest first. Categories beyond `limit` are folded into "Other".
    public static func byCategory(
        in snapshot: LedgerSnapshot,
        interval: DateInterval,
        limit: Int = .max
    ) -> [CategorySpend] {
        var totals: [CategoryID: (Money, Int)] = [:]
        for transaction in snapshot.transactions(in: interval) where transaction.kind == .expense {
            let current = totals[transaction.categoryID] ?? (.zero, 0)
            totals[transaction.categoryID] = (current.0 + transaction.amount, current.1 + 1)
        }
        let grandTotal = totals.values.sum(\.0)
        var sorted = totals
            .map { (id: $0.key, amount: $0.value.0, count: $0.value.1) }
            .sorted { ($0.amount, $1.id) > ($1.amount, $0.id) }

        if sorted.count > limit, limit > 0 {
            let tail = sorted[(limit - 1)...]
            let folded = (id: CategoryID.otherExpense, amount: tail.sum(\.amount), count: tail.reduce(0) { $0 + $1.count })
            sorted = Array(sorted.prefix(limit - 1)) + [folded]
        }
        return sorted.map {
            CategorySpend(categoryID: $0.id, amount: $0.amount, share: $0.amount.fraction(of: grandTotal), transactionCount: $0.count)
        }
    }

    /// Spending bucketed for a bar chart: by day for a week or month, by month for a year.
    public static func series(
        in snapshot: LedgerSnapshot,
        period: AnalyticsPeriod,
        now: Date,
        calendar: Calendar
    ) -> [DatedAmount] {
        let interval = period.interval(containing: now, calendar: calendar)
        let bucket: Calendar.Component = period == .year ? .month : .day
        var buckets: [Date: Money] = [:]
        var cursor = interval.start
        while cursor < interval.end {
            buckets[cursor] = .zero
            guard let next = calendar.date(byAdding: bucket, value: 1, to: cursor) else { break }
            cursor = next
        }
        for transaction in snapshot.transactions(in: interval) where transaction.kind == .expense {
            let key = calendar.dateInterval(of: bucket, for: transaction.date)?.start ?? transaction.date
            buckets[key, default: .zero] += transaction.amount
        }
        return buckets.map { DatedAmount(date: $0.key, amount: $0.value) }.sorted { $0.date < $1.date }
    }
}
