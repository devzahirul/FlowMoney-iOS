public import Domain
public import Foundation

/// A batch of rows moving between the device and the server, grouped by table.
public struct ChangeSet: Sendable, Equatable {
    public var profiles: [Profile] = []
    public var accounts: [Account] = []
    public var transactions: [LedgerTransaction] = []
    public var budgets: [Budget] = []
    public var goals: [Goal] = []
    public var contributions: [GoalContribution] = []
    public var recurringRules: [RecurringRule] = []

    public init(
        profiles: [Profile] = [],
        accounts: [Account] = [],
        transactions: [LedgerTransaction] = [],
        budgets: [Budget] = [],
        goals: [Goal] = [],
        contributions: [GoalContribution] = [],
        recurringRules: [RecurringRule] = []
    ) {
        self.profiles = profiles
        self.accounts = accounts
        self.transactions = transactions
        self.budgets = budgets
        self.goals = goals
        self.contributions = contributions
        self.recurringRules = recurringRules
    }

    public var count: Int {
        profiles.count + accounts.count + transactions.count + budgets.count
            + goals.count + contributions.count + recurringRules.count
    }

    public var isEmpty: Bool {
        profiles.isEmpty && accounts.isEmpty && transactions.isEmpty && budgets.isEmpty
            && goals.isEmpty && contributions.isEmpty && recurringRules.isEmpty
    }

    /// The newest server `updatedAt` in the batch — the next pull cursor.
    public var latestUpdate: Date? {
        [
            profiles.map(\.updatedAt).max(), accounts.map(\.updatedAt).max(), transactions.map(\.updatedAt).max(),
            budgets.map(\.updatedAt).max(), goals.map(\.updatedAt).max(), contributions.map(\.updatedAt).max(),
            recurringRules.map(\.updatedAt).max(),
        ].compactMap(\.self).max()
    }
}

public enum SyncError: Error, Equatable, Sendable {
    case offline
    /// The session expired or was revoked — the user must sign in again.
    case unauthorized
    case server(String)
}

/// What the sync engine needs from a backend. Implemented by `SupabaseBackend`; faked in tests.
public protocol RemoteLedgerService: Sendable {
    /// Upserts every row (idempotent: primary keys are client-generated). The server stamps `updatedAt`.
    func push(_ changes: ChangeSet) async throws(SyncError)
    /// Rows whose server `updatedAt` is after `since` (everything when `nil`), including tombstones.
    func pull(since: Date?) async throws(SyncError) -> ChangeSet
}
