public import FlowCore
public import Foundation

public struct GoalStatus: Identifiable, Sendable, Hashable {
    public let goal: Goal
    public let saved: Money
    /// Whole months from now until the target date (0 if due or no date).
    public let monthsLeft: Int?

    public var id: UUID {
        goal.id
    }

    public var remaining: Money {
        max(goal.target - saved, .zero)
    }

    public var fraction: Double {
        min(max(saved.fraction(of: goal.target), 0), 1)
    }

    public var isComplete: Bool {
        saved >= goal.target
    }

    /// Saving `monthlyContribution` every month from now reaches the target by the target date.
    public var isOnTrack: Bool {
        if isComplete {
            return true
        }
        guard let monthsLeft else { return goal.monthlyContribution.minorUnits > 0 }
        return saved + goal.monthlyContribution * monthsLeft >= goal.target
    }

    /// What must be saved each month from now to hit the date exactly.
    public var requiredMonthly: Money? {
        guard let monthsLeft, monthsLeft > 0 else { return nil }
        return Money(minorUnits: (remaining.minorUnits + Int64(monthsLeft) - 1) / Int64(monthsLeft))
    }

    /// Milestone reached, for celebratory notifications: 25, 50, 75 or 100.
    public var milestone: Int? {
        [100, 75, 50, 25].first { fraction * 100 >= Double($0) }
    }
}

public enum GoalProgress {
    public static func statuses(for snapshot: LedgerSnapshot, now: Date, calendar: Calendar) -> [GoalStatus] {
        snapshot.goals.map { status(for: $0, in: snapshot, now: now, calendar: calendar) }
    }

    public static func status(for goal: Goal, in snapshot: LedgerSnapshot, now: Date, calendar: Calendar) -> GoalStatus {
        let monthsLeft = goal.targetDate.map {
            max(0, YearMonth(now, calendar: calendar).months(to: YearMonth($0, calendar: calendar)))
        }
        return GoalStatus(goal: goal, saved: snapshot.saved(toward: goal.id), monthsLeft: monthsLeft)
    }

    /// Amount contributed per month for the goal detail chart, oldest first.
    public static func monthlyContributions(
        for goalID: UUID,
        in snapshot: LedgerSnapshot,
        months: Int,
        now: Date,
        calendar: Calendar
    ) -> [DatedAmount] {
        let current = YearMonth(now, calendar: calendar)
        var totals: [YearMonth: Money] = [:]
        for contribution in snapshot.contributions where contribution.goalID == goalID {
            totals[YearMonth(contribution.date, calendar: calendar), default: .zero] += contribution.amount
        }
        return current.trailing(months).map { DatedAmount(date: $0.firstDay(in: calendar), amount: totals[$0] ?? .zero) }
    }
}
