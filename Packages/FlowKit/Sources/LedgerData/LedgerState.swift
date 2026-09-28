public import Domain
public import Foundation

/// Everything persisted on the device for one user: all rows (including tombstones), the outbox of
/// unsynced changes and the pull cursor. Plain value type → trivially `Codable`, `Sendable` and testable.
public struct LedgerState: Codable, Sendable, Equatable {
    public var profile: Profile
    public var accounts: [UUID: Account] = [:]
    public var transactions: [UUID: LedgerTransaction] = [:]
    public var budgets: [UUID: Budget] = [:]
    public var goals: [UUID: Goal] = [:]
    public var contributions: [UUID: GoalContribution] = [:]
    public var recurringRules: [UUID: RecurringRule] = [:]

    /// Unsynced rows → local revision at the time of the last edit. Keyed by row, so ten edits to one
    /// transaction while offline upload as *one* upsert of the latest version.
    public var outbox: [RecordKey: Int] = [:]
    public var revision = 0
    /// Highest server `updatedAt` seen — the next pull asks for rows changed after this.
    public var syncCursor: Date?
    public var lastSyncedAt: Date?
    public var schemaVersion = LedgerState.currentSchemaVersion

    public static let currentSchemaVersion = 1

    public init(profile: Profile) {
        self.profile = profile
    }

    public init(demo content: DemoLedger.Content) {
        profile = content.profile
        accounts = Self.index(content.accounts)
        transactions = Self.index(content.transactions)
        budgets = Self.index(content.budgets)
        goals = Self.index(content.goals)
        contributions = Self.index(content.contributions)
        recurringRules = Self.index(content.recurringRules)
        revision = 1
    }

    static func index<Record: LedgerRecord>(_ records: [Record]) -> [UUID: Record] {
        Dictionary(records.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
    }

    public func snapshot() -> LedgerSnapshot {
        LedgerSnapshot(
            profile: profile,
            accounts: Array(accounts.values),
            transactions: Array(transactions.values),
            budgets: Array(budgets.values),
            goals: Array(goals.values),
            contributions: Array(contributions.values),
            recurringRules: Array(recurringRules.values),
            revision: revision
        )
    }

    // MARK: - Outbox

    /// The current version of every row in `keys`, grouped by table for upload.
    func changeSet(for keys: some Sequence<RecordKey>) -> ChangeSet {
        var changes = ChangeSet()
        for key in keys {
            switch key.kind {
            case .profile: if profile.id == key.id {
                    changes.profiles.append(profile)
                }
            case .account: accounts[key.id].map { changes.accounts.append($0) }
            case .transaction: transactions[key.id].map { changes.transactions.append($0) }
            case .budget: budgets[key.id].map { changes.budgets.append($0) }
            case .goal: goals[key.id].map { changes.goals.append($0) }
            case .goalContribution: contributions[key.id].map { changes.contributions.append($0) }
            case .recurringRule: recurringRules[key.id].map { changes.recurringRules.append($0) }
            }
        }
        return changes
    }

    // MARK: - Merge

    /// Applies rows pulled from the server. Rows with unsynced local edits are skipped — the local edit
    /// is newer by definition and will overwrite the server copy on the next push (last writer wins).
    /// Returns whether anything visible changed.
    mutating func merge(_ changes: ChangeSet) -> Bool {
        var changed = false
        func apply<Record: LedgerRecord>(_ rows: [Record], into table: WritableKeyPath<LedgerState, [UUID: Record]>) {
            for row in rows where outbox[row.key] == nil && self[keyPath: table][row.id] != row {
                self[keyPath: table][row.id] = row
                changed = true
            }
        }
        for incoming in changes.profiles where incoming.id == profile.id && outbox[incoming.key] == nil && incoming != profile {
            profile = incoming
            changed = true
        }
        apply(changes.accounts, into: \.accounts)
        apply(changes.transactions, into: \.transactions)
        apply(changes.budgets, into: \.budgets)
        apply(changes.goals, into: \.goals)
        apply(changes.contributions, into: \.contributions)
        apply(changes.recurringRules, into: \.recurringRules)
        if changed {
            revision += 1
        }
        return changed
    }
}
