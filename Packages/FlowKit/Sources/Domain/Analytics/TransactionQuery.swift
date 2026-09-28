public import FlowCore
public import Foundation

public enum TransactionFilter: String, CaseIterable, Sendable, Hashable, Identifiable {
    case all, income, expense

    public var id: Self {
        self
    }

    public var title: String {
        switch self {
        case .all: "All"
        case .income: "Income"
        case .expense: "Expenses"
        }
    }

    func matches(_ transaction: LedgerTransaction) -> Bool {
        switch self {
        case .all: true
        case .income: transaction.kind == .income
        case .expense: transaction.kind == .expense
        }
    }
}

public struct DaySection: Identifiable, Sendable, Hashable {
    public let day: Date
    public let transactions: [LedgerTransaction]
    public var id: Date {
        day
    }

    /// Net for the day (income − spending).
    public var net: Money {
        transactions.sum(\.signedAmount)
    }
}

public enum TransactionQuery {
    /// Case- and diacritic-insensitive search over merchant, note, category and account name.
    /// A numeric query ("5.20") also matches the amount.
    public static func search(
        _ text: String,
        filter: TransactionFilter = .all,
        in snapshot: LedgerSnapshot
    ) -> [LedgerTransaction] {
        let terms = normalize(text).split(separator: " ").map(String.init)
        let amountQuery = Decimal(string: text.trimmingCharacters(in: .whitespaces), locale: Locale(identifier: "en_US_POSIX"))
            .map { Money($0, fractionDigits: snapshot.currency.fractionDigits) }
        return snapshot.transactions.filter { transaction in
            guard filter.matches(transaction) else { return false }
            guard !terms.isEmpty else { return true }
            if let amountQuery, transaction.amount == amountQuery {
                return true
            }
            let haystack = normalize([
                transaction.merchant,
                transaction.note,
                transaction.category.name,
                snapshot.accountsByID[transaction.accountID]?.name ?? "",
            ].joined(separator: " "))
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    /// Groups (already newest-first) transactions by calendar day.
    public static func groupedByDay(_ transactions: some Sequence<LedgerTransaction>, calendar: Calendar) -> [DaySection] {
        var sections: [DaySection] = []
        var currentDay: Date?
        var bucket: [LedgerTransaction] = []
        for transaction in transactions {
            let day = calendar.startOfDay(for: transaction.date)
            if day != currentDay, let currentDay {
                sections.append(DaySection(day: currentDay, transactions: bucket))
                bucket.removeAll(keepingCapacity: true)
            }
            currentDay = day
            bucket.append(transaction)
        }
        if let currentDay {
            sections.append(DaySection(day: currentDay, transactions: bucket))
        }
        return sections
    }

    /// Spending and income per day of `month`, for the calendar view.
    public static func dailyTotals(
        for month: YearMonth,
        in snapshot: LedgerSnapshot,
        calendar: Calendar
    ) -> [Date: (income: Money, expense: Money)] {
        var totals: [Date: (income: Money, expense: Money)] = [:]
        for transaction in snapshot.transactions(in: month, calendar: calendar) {
            let day = calendar.startOfDay(for: transaction.date)
            var entry = totals[day] ?? (.zero, .zero)
            if transaction.kind == .income {
                entry.income += transaction.amount
            } else {
                entry.expense += transaction.amount
            }
            totals[day] = entry
        }
        return totals
    }

    static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
