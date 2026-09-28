public import FlowCore
public import Foundation

public struct LedgerAlert: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case budget, goal, largeTransaction, renewal, weeklyReport
    }

    /// Stable across launches so "read" state survives: derived from the subject + period, never random.
    public let id: String
    public let kind: Kind
    public let title: String
    public let message: String
    public let date: Date
    /// The budget, goal, transaction or recurring rule the alert is about — so a tap can open it.
    public var subjectID: UUID?

    /// Alerts need attention; the rest are updates.
    public var isAlert: Bool {
        kind == .budget || kind == .largeTransaction || kind == .renewal
    }
}

/// Derives the notification centre from the ledger instead of storing notifications: nothing to sync,
/// nothing to go stale, and an alert disappears by itself once its cause is fixed.
public enum AlertFeed {
    public static let largeTransactionThreshold = Money(minorUnits: 50000)
    public static let renewalLookaheadDays = 3

    public static func alerts(for snapshot: LedgerSnapshot, now: Date, calendar: Calendar) -> [LedgerAlert] {
        var alerts: [LedgerAlert] = []
        let month = YearMonth(now, calendar: calendar)
        let currency = snapshot.currency

        for status in BudgetProgress.summary(for: snapshot, month: month, now: now, calendar: calendar).statuses
            where status.level != .onTrack {
            let name = status.budget.categoryID.category.name
            let percent = Int((status.fraction * 100).rounded())
            alerts.append(LedgerAlert(
                id: "budget-\(status.budget.id)-\(month)-\(status.level == .over ? "over" : "near")",
                kind: .budget,
                title: status.level == .over ? "Budget exceeded" : "Budget alert",
                message: status.level == .over
                    ? "You're \(currency.string(-status.remaining)) over your \(name) budget."
                    : "You've used \(percent)% of your \(name) budget.",
                date: now,
                subjectID: status.budget.id
            ))
        }

        for status in GoalProgress.statuses(for: snapshot, now: now, calendar: calendar) {
            guard let milestone = status.milestone else { continue }
            let reachedAt = snapshot.contributions.first { $0.goalID == status.goal.id }?.date ?? status.goal.updatedAt
            alerts.append(LedgerAlert(
                id: "goal-\(status.goal.id)-\(milestone)",
                kind: .goal,
                title: milestone == 100 ? "Goal reached 🎉" : "Goal update",
                message: milestone == 100
                    ? "You reached your \(status.goal.name) goal!"
                    : "You're \(milestone)% of the way to your \(status.goal.name) goal.",
                date: reachedAt,
                subjectID: status.goal.id
            ))
        }

        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        for transaction in snapshot.transactions(in: DateInterval(start: weekAgo, end: now))
            where transaction.kind == .expense && transaction.amount >= largeTransactionThreshold {
            alerts.append(LedgerAlert(
                id: "large-\(transaction.id)",
                kind: .largeTransaction,
                title: "Large transaction",
                message: "\(currency.string(transaction.amount)) at \(transaction.displayTitle).",
                date: transaction.date,
                subjectID: transaction.id
            ))
        }

        let horizon = calendar.date(byAdding: .day, value: renewalLookaheadDays, to: now) ?? now
        for rule in snapshot.recurringRules where rule.isSubscription && !rule.isPaused {
            guard let next = rule.nextOccurrence(onOrAfter: now, calendar: calendar), next <= horizon else { continue }
            alerts.append(LedgerAlert(
                id: "renewal-\(rule.id)-\(Int(next.timeIntervalSince1970))",
                kind: .renewal,
                title: "Subscription renewal",
                message: "\(rule.name) renews \(RelativeDay.phrase(for: next, now: now, calendar: calendar))"
                    + " for \(currency.string(rule.amount)).",
                date: now,
                subjectID: rule.id
            ))
        }

        if let lastWeek = calendar.dateInterval(of: .weekOfYear, for: weekAgo) {
            let spent = snapshot.transactions(in: lastWeek).filter { $0.kind == .expense }.sum(\.amount)
            if !spent.isZero {
                alerts.append(LedgerAlert(
                    id: "weekly-\(Int(lastWeek.start.timeIntervalSince1970))",
                    kind: .weeklyReport,
                    title: "Weekly report",
                    message: "You spent \(currency.string(spent)) last week. Tap to see where it went.",
                    date: lastWeek.end
                ))
            }
        }
        return alerts.sorted { $0.date > $1.date }
    }
}

public enum RelativeDay {
    /// "today", "tomorrow", "in 3 days".
    public static func phrase(for date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case ..<1: return "today"
        case 1: return "tomorrow"
        default: return "in \(days) days"
        }
    }
}

public extension String {
    /// "in 3 days" → "In 3 days" (unlike `capitalized`, which gives "In 3 Days").
    var sentenceCased: String {
        prefix(1).uppercased() + dropFirst()
    }
}
