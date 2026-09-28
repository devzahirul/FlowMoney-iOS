import Domain
import FlowCore
import Foundation

/// Applies one `LedgerMutation` to `LedgerState`: validates it, stamps `updatedAt`, soft-deletes, cascades,
/// and records the touched rows in the outbox. Pure (no I/O), so every rule is unit-tested directly.
enum LedgerMutator {
    static func apply(_ mutation: LedgerMutation, to state: inout LedgerState, at now: Date) throws {
        switch mutation {
        case var .saveAccount(account):
            try require(!account.name.trimmingCharacters(in: .whitespaces).isEmpty, "Give the account a name.")
            account.name = account.name.trimmingCharacters(in: .whitespaces)
            upsert(account, into: \.accounts, state: &state, now: now)

        case let .deleteAccount(id):
            try softDelete(id, in: \.accounts, state: &state, now: now)
            for transaction in state.transactions.values where transaction.accountID == id && !transaction.isDeleted {
                try softDelete(transaction.id, in: \.transactions, state: &state, now: now)
            }
            for rule in state.recurringRules.values where rule.accountID == id && !rule.isDeleted {
                try softDelete(rule.id, in: \.recurringRules, state: &state, now: now)
            }

        case let .saveTransaction(transaction):
            try require(transaction.amount.minorUnits > 0, "Enter an amount greater than zero.")
            try require(state.accounts[transaction.accountID].map { !$0.isDeleted } == true, "Choose an account.")
            upsert(transaction, into: \.transactions, state: &state, now: now)

        case let .deleteTransaction(id):
            try softDelete(id, in: \.transactions, state: &state, now: now)

        case var .saveBudget(budget):
            try require(budget.limit.minorUnits > 0, "Set a limit greater than zero.")
            // One live budget per category: saving a second one replaces the first rather than duplicating.
            if let existing = state.budgets.values.first(where: {
                $0.categoryID == budget.categoryID && !$0.isDeleted && $0.id != budget.id
            }) {
                budget = Budget(id: existing.id, categoryID: budget.categoryID, limit: budget.limit, createdAt: existing.createdAt)
            }
            upsert(budget, into: \.budgets, state: &state, now: now)

        case let .deleteBudget(id):
            try softDelete(id, in: \.budgets, state: &state, now: now)

        case var .saveGoal(goal):
            try require(!goal.name.trimmingCharacters(in: .whitespaces).isEmpty, "Give the goal a name.")
            try require(goal.target.minorUnits > 0, "Set a target greater than zero.")
            goal.name = goal.name.trimmingCharacters(in: .whitespaces)
            upsert(goal, into: \.goals, state: &state, now: now)

        case let .deleteGoal(id):
            try softDelete(id, in: \.goals, state: &state, now: now)
            for contribution in state.contributions.values where contribution.goalID == id && !contribution.isDeleted {
                try softDelete(contribution.id, in: \.contributions, state: &state, now: now)
            }

        case let .saveContribution(contribution):
            try require(!contribution.amount.isZero, "Enter an amount.")
            try require(state.goals[contribution.goalID].map { !$0.isDeleted } == true, "That goal no longer exists.")
            upsert(contribution, into: \.contributions, state: &state, now: now)

        case let .deleteContribution(id):
            try softDelete(id, in: \.contributions, state: &state, now: now)

        case let .saveRecurringRule(rule):
            try require(!rule.name.trimmingCharacters(in: .whitespaces).isEmpty, "Give it a name.")
            try require(rule.amount.minorUnits > 0, "Enter an amount greater than zero.")
            try require(state.accounts[rule.accountID].map { !$0.isDeleted } == true, "Choose an account.")
            upsert(rule, into: \.recurringRules, state: &state, now: now)

        case let .deleteRecurringRule(id):
            try softDelete(id, in: \.recurringRules, state: &state, now: now)

        case var .updateProfile(profile):
            try require(profile.id == state.profile.id, "Profile mismatch.")
            profile.displayName = profile.displayName.trimmingCharacters(in: .whitespaces)
            try require(!profile.displayName.isEmpty, "Enter your name.")
            guard profile != state.profile else { return }
            profile.updatedAt = now
            state.profile = profile
            touch(profile.key, state: &state)
        }
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw LedgerError.invalid(message)
        }
    }

    private static func upsert<Record: LedgerRecord>(
        _ record: Record,
        into table: WritableKeyPath<LedgerState, [UUID: Record]>,
        state: inout LedgerState,
        now: Date
    ) {
        var record = record
        // Compare ignoring timestamps: re-saving an unchanged form must not create a sync round-trip.
        if var existing = state[keyPath: table][record.id] {
            existing.updatedAt = record.updatedAt
            if existing == record {
                return
            }
        }
        record.updatedAt = now
        state[keyPath: table][record.id] = record
        touch(record.key, state: &state)
    }

    private static func softDelete(
        _ id: UUID,
        in table: WritableKeyPath<LedgerState, [UUID: some LedgerRecord]>,
        state: inout LedgerState,
        now: Date
    ) throws {
        guard var record = state[keyPath: table][id], !record.isDeleted else { throw LedgerError.notFound }
        record.deletedAt = now
        record.updatedAt = now
        state[keyPath: table][id] = record
        touch(record.key, state: &state)
    }

    private static func touch(_ key: RecordKey, state: inout LedgerState) {
        state.outbox[key] = state.revision + 1
    }
}
