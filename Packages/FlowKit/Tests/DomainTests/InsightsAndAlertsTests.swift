@testable import Domain
import FlowCore
import Foundation
import Testing
import TestSupport

@Suite("InsightEngine")
struct InsightEngineTests {
    let calendar = TestCalendar.utc
    let now = TestCalendar.date(2026, 3, 10)

    @Test("Compares month-to-date with the same days of last month")
    func categoryTrendIsFair() {
        let snapshot = Fixture.snapshot(transactions: [
            Fixture.expense(.dollars(100), .food, on: TestCalendar.date(2026, 2, 5)),
            // Late February spend must be ignored on March 10, or March would always look cheaper.
            Fixture.expense(.dollars(900), .food, on: TestCalendar.date(2026, 2, 25)),
            Fixture.expense(.dollars(132), .food, on: TestCalendar.date(2026, 3, 5)),
        ])
        let insight = InsightEngine.categoryTrend(snapshot, now: now, calendar: calendar).first
        #expect(insight?.tone == .warning)
        #expect(insight?.message.contains("32% more on Food & Drink") == true)
    }

    @Test("Small changes and tiny baselines produce no noise")
    func ignoresNoise() {
        let snapshot = Fixture.snapshot(transactions: [
            Fixture.expense(.dollars(100), .food, on: TestCalendar.date(2026, 2, 5)),
            Fixture.expense(.dollars(105), .food, on: TestCalendar.date(2026, 3, 5)),
            Fixture.expense(.dollars(2), .travel, on: TestCalendar.date(2026, 2, 5)),
            Fixture.expense(.dollars(50), .travel, on: TestCalendar.date(2026, 3, 5)),
        ])
        #expect(InsightEngine.categoryTrend(snapshot, now: now, calendar: calendar).isEmpty)
    }

    @Test("Healthy savings rate is celebrated, overspending is flagged")
    func savingsRate() {
        let good = Fixture.snapshot(transactions: [
            Fixture.income(.dollars(1000), on: TestCalendar.date(2026, 3, 1)),
            Fixture.expense(.dollars(500), on: TestCalendar.date(2026, 3, 2)),
        ])
        #expect(InsightEngine.savingsRate(good, now: now, calendar: calendar).first?.tone == .positive)
        let bad = Fixture.snapshot(transactions: [
            Fixture.income(.dollars(100), on: TestCalendar.date(2026, 3, 1)),
            Fixture.expense(.dollars(500), on: TestCalendar.date(2026, 3, 2)),
        ])
        #expect(InsightEngine.savingsRate(bad, now: now, calendar: calendar).first?.tone == .warning)
    }

    @Test("Subscription cost is summarised monthly and yearly")
    func subscriptions() {
        let snapshot = Fixture.snapshot(rules: [
            Fixture.rule(name: "A", amount: .dollars(10), start: now),
            Fixture.rule(name: "B", amount: .dollars(120), frequency: .yearly, start: now),
        ])
        let insight = InsightEngine.subscriptions(snapshot).first
        #expect(insight?.message == "You have 2 active subscriptions costing $20.00 a month.")
        #expect(insight?.tip?.contains("$240.00 a year") == true)
    }
}

@Suite("AlertFeed")
struct AlertFeedTests {
    let calendar = TestCalendar.utc
    let now = TestCalendar.date(2026, 3, 10)

    @Test("Budget, large transaction and renewal alerts with stable IDs")
    func alerts() {
        let budget = Fixture.budget(.food, limit: .dollars(100))
        let big = Fixture.expense(.dollars(750), .shopping, on: TestCalendar.date(2026, 3, 8), merchant: "Apple Store")
        let snapshot = Fixture.snapshot(
            transactions: [Fixture.expense(.dollars(85), .food, on: TestCalendar.date(2026, 3, 2)), big],
            budgets: [budget],
            rules: [Fixture.rule(name: "Netflix", start: TestCalendar.date(2026, 1, 12))]
        )
        let alerts = AlertFeed.alerts(for: snapshot, now: now, calendar: calendar)
        let kinds = Set(alerts.map(\.kind))
        #expect(kinds.isSuperset(of: [.budget, .largeTransaction, .renewal]))
        #expect(alerts.first { $0.kind == .renewal }?.message == "Netflix renews in 2 days for $15.99.")
        #expect(alerts.first { $0.kind == .budget }?.message == "You've used 85% of your Food & Drink budget.")
        #expect(AlertFeed.alerts(for: snapshot, now: now, calendar: calendar).map(\.id) == alerts.map(\.id))
    }

    @Test("Alert disappears once its cause is gone")
    func selfResolving() {
        let snapshot = Fixture.snapshot(budgets: [Fixture.budget(.food, limit: .dollars(100))])
        #expect(AlertFeed.alerts(for: snapshot, now: now, calendar: calendar).allSatisfy { $0.kind != .budget })
    }
}

@Suite("MonthlyReport")
struct MonthlyReportTests {
    @Test("Headline compares with last month")
    func headline() {
        let snapshot = Fixture.snapshot(transactions: [
            Fixture.expense(.dollars(100), on: TestCalendar.date(2026, 2, 3)),
            Fixture.expense(.dollars(88), on: TestCalendar.date(2026, 3, 3)),
        ])
        let report = MonthlyReport.make(
            for: YearMonth(year: 2026, month: 3), in: snapshot, now: TestCalendar.date(2026, 4, 2), calendar: TestCalendar.utc
        )
        #expect(report.headline == "You spent 12% less than last month 🎉")
        #expect(report.dailyAverage == Money(minorUnits: 8800 / 31))
        #expect(report.largestExpense?.amount == .dollars(88))
    }
}
