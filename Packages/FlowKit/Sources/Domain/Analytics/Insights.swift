public import Foundation
import FlowCore

public struct Insight: Identifiable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case spending, saving, goal, subscription, budget
    }

    public enum Tone: Sendable, Hashable {
        case positive, neutral, warning
    }

    public let id: String
    public let kind: Kind
    public let tone: Tone
    public let title: String
    public let message: String
    public let tip: String?
}

/// Turns the ledger into plain-language advice. Deterministic and pure, so every rule is unit-tested.
public enum InsightEngine {
    public static func insights(for snapshot: LedgerSnapshot, now: Date, calendar: Calendar) -> [Insight] {
        var result: [Insight] = []
        result += categoryTrend(snapshot, now: now, calendar: calendar)
        result += savingsRate(snapshot, now: now, calendar: calendar)
        result += budgetWarnings(snapshot, now: now, calendar: calendar)
        result += goals(snapshot, now: now, calendar: calendar)
        result += subscriptions(snapshot)
        return result
    }

    /// Compares month-to-date with the *same number of days* last month, so the 5th of the month
    /// isn't compared against a whole previous month (which would always look like a huge drop).
    static func categoryTrend(_ snapshot: LedgerSnapshot, now: Date, calendar: Calendar) -> [Insight] {
        let month = YearMonth(now, calendar: calendar)
        let day = calendar.component(.day, from: now)
        let currentStart = month.firstDay(in: calendar)
        let previousStart = month.previous.firstDay(in: calendar)
        let previousDays = min(day, month.previous.dayCount(in: calendar))
        guard let currentEnd = calendar.date(byAdding: .day, value: day, to: currentStart),
              let previousEnd = calendar.date(byAdding: .day, value: previousDays, to: previousStart) else { return [] }

        let current = SpendingBreakdown.byCategory(in: snapshot, interval: DateInterval(start: currentStart, end: currentEnd))
        let previous = Dictionary(uniqueKeysWithValues: SpendingBreakdown
            .byCategory(in: snapshot, interval: DateInterval(start: previousStart, end: previousEnd))
            .map { ($0.categoryID, $0.amount) })

        let changes = current.compactMap { spend -> (CategorySpend, Double)? in
            guard let before = previous[spend.categoryID], before.minorUnits >= 1000,
                  let change = CashFlow.change(from: before, to: spend.amount) else { return nil }
            return (spend, change)
        }
        guard let (spend, change) = changes.max(by: { abs($0.1) < abs($1.1) }), abs(change) >= 0.15 else { return [] }
        let percent = Int((abs(change) * 100).rounded())
        let name = spend.category.name
        if change > 0 {
            return [Insight(
                id: "trend-\(spend.categoryID.rawValue)",
                kind: .spending,
                tone: .warning,
                title: "Spending insight",
                message: "You've spent \(percent)% more on \(name) than this time last month.",
                tip: "Try setting a \(name) budget to keep it in check."
            )]
        }
        return [Insight(
            id: "trend-\(spend.categoryID.rawValue)",
            kind: .spending,
            tone: .positive,
            title: "Spending insight",
            message: "You've spent \(percent)% less on \(name) than this time last month. Nice!",
            tip: nil
        )]
    }

    static func savingsRate(_ snapshot: LedgerSnapshot, now: Date, calendar: Calendar) -> [Insight] {
        let flow = CashFlow.month(YearMonth(now, calendar: calendar), in: snapshot, calendar: calendar)
        guard flow.income.minorUnits > 0 else { return [] }
        let percent = Int((flow.savingsRate * 100).rounded())
        if percent >= 20 {
            return [Insight(
                id: "savings-rate",
                kind: .saving,
                tone: .positive,
                title: "Savings insight",
                message: "You've kept \(percent)% of your income this month.",
                tip: "Keep going — 20% or more is a healthy savings rate."
            )]
        }
        if percent < 0 {
            return [Insight(
                id: "savings-rate",
                kind: .saving,
                tone: .warning,
                title: "Savings insight",
                message: "You've spent more than you earned this month.",
                tip: "Review your top categories to find quick wins."
            )]
        }
        return []
    }

    static func budgetWarnings(_ snapshot: LedgerSnapshot, now: Date, calendar: Calendar) -> [Insight] {
        let summary = BudgetProgress.summary(for: snapshot, month: YearMonth(now, calendar: calendar), now: now, calendar: calendar)
        return summary.statuses
            .filter { $0.level == .onTrack && $0.isProjectedOver }
            .prefix(2)
            .map { status in
                Insight(
                    id: "budget-pace-\(status.budget.categoryID.rawValue)",
                    kind: .budget,
                    tone: .warning,
                    title: "Budget insight",
                    message: "At this pace you'll go over your \(status.budget.categoryID.category.name) budget before month end.",
                    tip: "You have \(snapshot.currency.string(status.remaining)) left for the rest of the month."
                )
            }
    }

    static func goals(_ snapshot: LedgerSnapshot, now: Date, calendar: Calendar) -> [Insight] {
        GoalProgress.statuses(for: snapshot, now: now, calendar: calendar)
            .filter { !$0.isComplete }
            .prefix(2)
            .map { status in
                if status.isOnTrack {
                    return Insight(
                        id: "goal-\(status.goal.id)",
                        kind: .goal,
                        tone: .positive,
                        title: "Savings insight",
                        message: "You're on track to reach your \(status.goal.name) goal.",
                        tip: "You've saved \(Int((status.fraction * 100).rounded()))% so far."
                    )
                }
                let needed = status.requiredMonthly.map { snapshot.currency.string($0) } ?? "a bit more"
                return Insight(
                    id: "goal-\(status.goal.id)",
                    kind: .goal,
                    tone: .warning,
                    title: "Goal insight",
                    message: "Your \(status.goal.name) goal is falling behind.",
                    tip: "Save \(needed) a month to reach it on time."
                )
            }
    }

    static func subscriptions(_ snapshot: LedgerSnapshot) -> [Insight] {
        let active = snapshot.recurringRules.filter { $0.isSubscription && !$0.isPaused }
        guard active.count >= 2 else { return [] }
        let monthly = active.sum(\.monthlyEquivalent)
        return [Insight(
            id: "subscriptions",
            kind: .subscription,
            tone: .neutral,
            title: "Subscription insight",
            message: "You have \(active.count) active subscriptions costing \(snapshot.currency.string(monthly)) a month.",
            tip: "That's \(snapshot.currency.string(monthly * 12)) a year — cancel the ones you don't use."
        )]
    }
}
