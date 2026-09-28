public import FlowCore
public import Foundation

/// An immutable, consistent view of everything the user has — what every screen renders from.
///
/// Built off the main thread by the repository actor, including the indexes below, so screens get O(1)
/// lookups ("balance of account X", "saved toward goal Y") without scanning thousands of rows per frame.
public struct LedgerSnapshot: Sendable {
    public let profile: Profile
    /// Sorted by `sortOrder`, then name.
    public let accounts: [Account]
    /// Newest first.
    public let transactions: [LedgerTransaction]
    public let budgets: [Budget]
    public let goals: [Goal]
    public let contributions: [GoalContribution]
    public let recurringRules: [RecurringRule]
    /// Increments on every change; screens use it to skip recomputing derived state.
    public let revision: Int

    public let accountsByID: [UUID: Account]
    public let balances: [UUID: Money]
    public let savedByGoal: [UUID: Money]
    /// Built once per snapshot — creating currency formatters per row is a measurable scroll cost.
    public let currency: CurrencyFormat

    public init(
        profile: Profile,
        accounts: [Account] = [],
        transactions: [LedgerTransaction] = [],
        budgets: [Budget] = [],
        goals: [Goal] = [],
        contributions: [GoalContribution] = [],
        recurringRules: [RecurringRule] = [],
        revision: Int = 0
    ) {
        self.profile = profile
        self.accounts = accounts.filter { !$0.isDeleted }.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
        let liveAccountIDs = Set(self.accounts.map(\.id))
        self.transactions = transactions
            .filter { !$0.isDeleted && liveAccountIDs.contains($0.accountID) }
            .sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
        self.budgets = budgets.filter { !$0.isDeleted }.sorted { $0.categoryID.category.name < $1.categoryID.category.name }
        self.goals = goals.filter { !$0.isDeleted }.sorted { $0.createdAt < $1.createdAt }
        let liveGoalIDs = Set(self.goals.map(\.id))
        self.contributions = contributions
            .filter { !$0.isDeleted && liveGoalIDs.contains($0.goalID) }
            .sorted { $0.date > $1.date }
        self.recurringRules = recurringRules.filter { !$0.isDeleted }.sorted { $0.name < $1.name }
        self.revision = revision

        accountsByID = Dictionary(uniqueKeysWithValues: self.accounts.map { ($0.id, $0) })
        var balances = Dictionary(uniqueKeysWithValues: self.accounts.map { ($0.id, $0.openingBalance) })
        for transaction in self.transactions {
            balances[transaction.accountID]? += transaction.signedAmount
        }
        self.balances = balances
        var saved: [UUID: Money] = [:]
        for contribution in self.contributions {
            saved[contribution.goalID, default: .zero] += contribution.amount
        }
        savedByGoal = saved
        currency = CurrencyFormat(currencyCode: profile.currencyCode)
    }

    public func balance(of accountID: UUID) -> Money {
        balances[accountID] ?? .zero
    }

    public func saved(toward goalID: UUID) -> Money {
        savedByGoal[goalID] ?? .zero
    }

    /// Sum of every account balance (assets minus debts).
    public var totalBalance: Money {
        accounts.sum { balance(of: $0.id) }
    }

    public var isEmpty: Bool {
        accounts.isEmpty && transactions.isEmpty
    }

    public func transactions(in interval: DateInterval) -> some Collection<LedgerTransaction> {
        // `transactions` is sorted newest-first, so a binary search bounds the slice instead of a full scan.
        let upper = transactions.partitioningIndex { $0.date < interval.end }
        let lower = transactions.partitioningIndex { $0.date < interval.start }
        return transactions[upper ..< lower]
    }

    public func transactions(in month: YearMonth, calendar: Calendar) -> some Collection<LedgerTransaction> {
        transactions(in: month.interval(in: calendar))
    }

    public static func empty(userID: UUID, name: String = "") -> LedgerSnapshot {
        LedgerSnapshot(profile: Profile(id: userID, displayName: name))
    }
}

extension RandomAccessCollection {
    /// First index where `predicate` becomes true, assuming the collection is partitioned (false… then true…).
    func partitioningIndex(where predicate: (Element) -> Bool) -> Index {
        var low = startIndex
        var high = endIndex
        while low != high {
            let mid = index(low, offsetBy: distance(from: low, to: high) / 2)
            if predicate(self[mid]) {
                high = mid
            } else {
                low = index(after: mid)
            }
        }
        return low
    }
}
