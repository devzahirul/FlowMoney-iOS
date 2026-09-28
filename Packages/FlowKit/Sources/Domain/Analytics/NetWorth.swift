public import FlowCore
public import Foundation

public struct NetWorthSummary: Sendable, Hashable {
    public struct Line: Sendable, Hashable, Identifiable {
        public let kind: AccountKind
        public let total: Money
        public var id: AccountKind {
            kind
        }
    }

    public let assets: Money
    /// Stored as a negative number (money owed).
    public let liabilities: Money
    public let lines: [Line]
    /// Month-end net worth for the trailing months, oldest first; the last point is "now".
    public let history: [DatedAmount]

    public var total: Money {
        assets + liabilities
    }

    /// Change since the end of last month.
    public var monthChange: Money {
        guard history.count >= 2 else { return .zero }
        return history[history.count - 1].amount - history[history.count - 2].amount
    }
}

public enum NetWorth {
    public static func summary(
        for snapshot: LedgerSnapshot,
        months: Int,
        now: Date,
        calendar: Calendar
    ) -> NetWorthSummary {
        var byKind: [AccountKind: Money] = [:]
        var assets = Money.zero
        var liabilities = Money.zero
        for account in snapshot.accounts {
            let balance = snapshot.balance(of: account.id)
            byKind[account.kind, default: .zero] += balance
            if account.kind.isLiability || balance.isNegative {
                liabilities += balance
            } else {
                assets += balance
            }
        }
        let lines = AccountKind.allCases.compactMap { kind in
            byKind[kind].map { NetWorthSummary.Line(kind: kind, total: $0) }
        }
        return NetWorthSummary(
            assets: assets,
            liabilities: liabilities,
            lines: lines,
            history: history(for: snapshot, months: months, now: now, calendar: calendar)
        )
    }

    /// Net worth at the end of each of the last `months` months (the current month uses `now`).
    ///
    /// Walks transactions newest→oldest once, "un-applying" them to step back in time: O(n + months).
    static func history(for snapshot: LedgerSnapshot, months: Int, now: Date, calendar: Calendar) -> [DatedAmount] {
        let current = YearMonth(now, calendar: calendar)
        var points: [DatedAmount] = []
        var running = snapshot.totalBalance
        var index = snapshot.transactions.startIndex
        // Future-dated rows (scheduled) don't count toward "now".
        while index < snapshot.transactions.endIndex, snapshot.transactions[index].date > now {
            running -= snapshot.transactions[index].signedAmount
            index += 1
        }
        points.append(DatedAmount(date: now, amount: running))
        for offset in 1 ..< max(months, 1) {
            let boundary = current.adding(months: -offset + 1).firstDay(in: calendar)
            while index < snapshot.transactions.endIndex, snapshot.transactions[index].date >= boundary {
                running -= snapshot.transactions[index].signedAmount
                index += 1
            }
            points.append(DatedAmount(date: boundary.addingTimeInterval(-1), amount: running))
        }
        return points.reversed()
    }
}
