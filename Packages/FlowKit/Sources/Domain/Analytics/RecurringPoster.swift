public import Foundation

/// Turns due recurring rules into transactions.
///
/// Each posted row gets a deterministic ID (`rule.postedTransactionID(for:)`), which makes posting
/// idempotent everywhere: running it twice, on two devices, or after a crash never duplicates rent. If the
/// user deletes a posted occurrence, its tombstone keeps the ID "taken", so it is not re-posted either.
public enum RecurringPoster {
    public static func dueTransactions(
        rules: [RecurringRule],
        existingIDs: Set<UUID>,
        now: Date,
        calendar: Calendar
    ) -> [LedgerTransaction] {
        rules.flatMap { rule -> [LedgerTransaction] in
            guard rule.autoPost, !rule.isPaused, !rule.isDeleted else { return [] }
            // Never back-fill before the rule existed: adding "Rent since 2019" must not create 80 rows.
            let from = max(rule.startDate, calendar.startOfDay(for: rule.createdAt))
            return rule.occurrences(from: from, through: now, calendar: calendar).compactMap { date in
                let id = rule.postedTransactionID(for: date, calendar: calendar)
                guard !existingIDs.contains(id) else { return nil }
                return LedgerTransaction(
                    id: id,
                    accountID: rule.accountID,
                    kind: rule.kind,
                    amount: rule.amount,
                    categoryID: rule.categoryID,
                    merchant: rule.name,
                    date: date,
                    recurringRuleID: rule.id,
                    createdAt: now,
                    updatedAt: now
                )
            }
        }
    }
}
