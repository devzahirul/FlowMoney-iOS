@testable import Domain
import FlowCore
import Foundation
import Testing
import TestSupport

@Suite("GoalProgress")
struct GoalProgressTests {
    let calendar = TestCalendar.utc
    let now = TestCalendar.date(2026, 3, 15)

    func status(saved: Money, target: Money, monthly: Money, due: Date?) -> GoalStatus {
        let goal = Fixture.goal(target: target, targetDate: due, monthly: monthly)
        let snapshot = Fixture.snapshot(goals: [goal], contributions: [Fixture.contribution(saved, to: goal.id, on: now)])
        return GoalProgress.status(for: goal, in: snapshot, now: now, calendar: calendar)
    }

    @Test("On track when planned monthly saving reaches the target by the date")
    func onTrack() {
        // 10 months × $300 + $2,400 = $5,400 ≥ $5,000
        let due = TestCalendar.date(2027, 1, 1)
        #expect(status(saved: .dollars(2400), target: .dollars(5000), monthly: .dollars(300), due: due).isOnTrack)
        #expect(!status(saved: .dollars(2400), target: .dollars(5000), monthly: .dollars(200), due: due).isOnTrack)
    }

    @Test("Required monthly amount rounds up so the goal is never missed by a cent")
    func requiredMonthly() {
        let result = status(saved: .zero, target: .dollars(100), monthly: .zero, due: TestCalendar.date(2026, 6, 1))
        #expect(result.monthsLeft == 3)
        #expect(result.requiredMonthly == Money(minorUnits: 3334))
    }

    @Test(arguments: [(0.0, Int?.none), (24.0, nil), (25.0, 25), (74.0, 50), (100.0, 100), (130.0, 100)])
    func milestones(percent: Double, expected: Int?) {
        let result = status(saved: .dollars(percent), target: .dollars(100), monthly: .zero, due: nil)
        #expect(result.milestone == expected)
    }

    @Test("Fraction is clamped to 0…1")
    func clamped() {
        #expect(status(saved: .dollars(150), target: .dollars(100), monthly: .zero, due: nil).fraction == 1)
        #expect(status(saved: .dollars(-10), target: .dollars(100), monthly: .zero, due: nil).fraction == 0)
    }
}

@Suite("NetWorth")
struct NetWorthTests {
    let calendar = TestCalendar.utc

    @Test("Liabilities are separated from assets")
    func split() {
        let card = Fixture.account(id: UUID(), name: "Card", kind: .creditCard, opening: .dollars(-500))
        let snapshot = Fixture.snapshot(accounts: [Fixture.account(opening: .dollars(2000)), card])
        let summary = NetWorth.summary(for: snapshot, months: 1, now: TestCalendar.date(2026, 3, 1), calendar: calendar)
        #expect(summary.assets == .dollars(2000))
        #expect(summary.liabilities == .dollars(-500))
        #expect(summary.total == .dollars(1500))
    }

    @Test("History steps back month by month by un-applying transactions")
    func history() {
        let snapshot = Fixture.snapshot(
            accounts: [Fixture.account(opening: .dollars(1000))],
            transactions: [
                Fixture.income(.dollars(500), on: TestCalendar.date(2026, 2, 10)),
                Fixture.expense(.dollars(200), on: TestCalendar.date(2026, 3, 5)),
                Fixture.expense(.dollars(999), on: TestCalendar.date(2026, 3, 20)), // future: excluded from "now"
            ]
        )
        let summary = NetWorth.summary(for: snapshot, months: 3, now: TestCalendar.date(2026, 3, 15), calendar: calendar)
        #expect(summary.history.map(\.amount) == [.dollars(1000), .dollars(1500), .dollars(1300)])
        #expect(summary.monthChange == .dollars(-200))
    }
}

@Suite("Recurrence")
struct RecurrenceTests {
    let calendar = TestCalendar.utc

    @Test("Monthly rules clamp to month end without drifting (Jan 31 → Feb 28 → Mar 31)")
    func monthEnd() {
        let rule = Fixture.rule(start: TestCalendar.date(2026, 1, 31))
        let dates = rule.occurrences(from: TestCalendar.date(2026, 1, 1), through: TestCalendar.date(2026, 4, 30), calendar: calendar)
        #expect(dates.map { calendar.component(.day, from: $0) } == [31, 28, 31, 30])
    }

    @Test("Next occurrence is found without walking every past date")
    func nextOccurrence() {
        let rule = Fixture.rule(frequency: .weekly, start: TestCalendar.date(2016, 1, 4))
        let next = rule.nextOccurrence(onOrAfter: TestCalendar.date(2026, 3, 11), calendar: calendar)
        #expect(next.map { calendar.component(.weekday, from: $0) } == 2) // Mondays
        #expect(next.map { $0 >= TestCalendar.date(2026, 3, 11, hour: 0) } == true)
    }

    @Test("Occurrence on the query day itself counts")
    func sameDay() {
        let rule = Fixture.rule(start: TestCalendar.date(2026, 1, 15, hour: 9))
        let next = rule.nextOccurrence(onOrAfter: TestCalendar.date(2026, 3, 15, hour: 18), calendar: calendar)
        #expect(next == TestCalendar.date(2026, 3, 15, hour: 9))
    }

    @Test("Monthly equivalent cost")
    func monthlyEquivalent() {
        #expect(Fixture.rule(amount: .dollars(120), frequency: .yearly, start: .now).monthlyEquivalent == .dollars(10))
        #expect(Fixture.rule(amount: .dollars(10), frequency: .weekly, start: .now).monthlyEquivalent == Money(minorUnits: 4333))
    }
}

@Suite("RecurringPoster")
struct RecurringPosterTests {
    let calendar = TestCalendar.utc
    let now = TestCalendar.date(2026, 3, 20)

    @Test("Posts each due occurrence once, with deterministic IDs")
    func postsDue() {
        let rule = Fixture.rule(start: TestCalendar.date(2026, 1, 3))
        let first = RecurringPoster.dueTransactions(rules: [rule], existingIDs: [], now: now, calendar: calendar)
        #expect(first.count == 3)
        #expect(first.allSatisfy { $0.recurringRuleID == rule.id && $0.amount == rule.amount })

        let again = RecurringPoster.dueTransactions(rules: [rule], existingIDs: Set(first.map(\.id)), now: now, calendar: calendar)
        #expect(again.isEmpty)

        let otherDevice = RecurringPoster.dueTransactions(rules: [rule], existingIDs: [], now: now, calendar: calendar)
        #expect(otherDevice.map(\.id) == first.map(\.id))
    }

    @Test("Never back-fills before the rule was created")
    func noBackfill() {
        let rule = Fixture.rule(start: TestCalendar.date(2019, 1, 1), createdAt: TestCalendar.date(2026, 3, 1))
        let posted = RecurringPoster.dueTransactions(rules: [rule], existingIDs: [], now: now, calendar: calendar)
        #expect(posted.count == 1)
    }

    @Test("Paused and manual rules post nothing")
    func pausedOrManual() {
        var paused = Fixture.rule(start: TestCalendar.date(2026, 1, 3))
        paused.isPaused = true
        var manual = Fixture.rule(start: TestCalendar.date(2026, 1, 3))
        manual.autoPost = false
        #expect(RecurringPoster.dueTransactions(rules: [paused, manual], existingIDs: [], now: now, calendar: calendar).isEmpty)
    }
}
