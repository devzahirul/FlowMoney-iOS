@testable import Domain
import FlowCore
import Foundation
import Testing
import TestSupport

@Suite("BudgetProgress")
struct BudgetProgressTests {
    let calendar = TestCalendar.utc
    let march = YearMonth(year: 2026, month: 3)

    func summary(spent: [Money], limit: Money, now: Date) -> BudgetStatus {
        let snapshot = Fixture.snapshot(
            transactions: spent.map { Fixture.expense($0, .food, on: TestCalendar.date(2026, 3, 2)) }
                + [Fixture.expense(.dollars(999), .shopping, on: TestCalendar.date(2026, 3, 2))] // other category ignored
                + [Fixture.expense(.dollars(999), .food, on: TestCalendar.date(2026, 2, 27))], // other month ignored
            budgets: [Fixture.budget(.food, limit: limit)]
        )
        return BudgetProgress.summary(for: snapshot, month: march, now: now, calendar: calendar).statuses[0]
    }

    @Test(arguments: [
        (100.0, BudgetStatus.Level.onTrack),
        (399.0, .onTrack),
        (400.0, .nearLimit),
        (500.0, .nearLimit),
        (500.01, .over),
    ])
    func levels(spent: Double, expected: BudgetStatus.Level) {
        let status = summary(spent: [.dollars(spent)], limit: .dollars(500), now: TestCalendar.date(2026, 4, 1))
        #expect(status.level == expected)
    }

    @Test("Only this month's spending in this category counts")
    func spentIsScoped() {
        let status = summary(spent: [.dollars(20), .dollars(30)], limit: .dollars(500), now: TestCalendar.date(2026, 3, 31))
        #expect(status.spent == .dollars(50))
        #expect(status.remaining == .dollars(450))
    }

    @Test("Projects spend to month end at the current pace")
    func projection() {
        // $100 by March 10 → 31/10 × 100 = $310 projected.
        let status = summary(spent: [.dollars(100)], limit: .dollars(300), now: TestCalendar.date(2026, 3, 10))
        #expect(status.projected == .dollars(310))
        #expect(status.isProjectedOver)
        #expect(status.level == .onTrack)
    }

    @Test("Past months are not extrapolated")
    func pastMonthNotProjected() {
        let status = summary(spent: [.dollars(100)], limit: .dollars(300), now: TestCalendar.date(2026, 5, 10))
        #expect(status.projected == .dollars(100))
    }
}

@Suite("CashFlow")
struct CashFlowTests {
    let calendar = TestCalendar.utc

    @Test("Buckets income and spending by month, oldest first, including empty months")
    func trailing() {
        let snapshot = Fixture.snapshot(transactions: [
            Fixture.income(.dollars(3000), on: TestCalendar.date(2026, 1, 1)),
            Fixture.expense(.dollars(1200), on: TestCalendar.date(2026, 1, 5)),
            Fixture.expense(.dollars(50), on: TestCalendar.date(2026, 3, 5)),
        ])
        let flows = CashFlow.trailing(3, endingAt: YearMonth(year: 2026, month: 3), in: snapshot, calendar: calendar)
        #expect(flows.map(\.month.month) == [1, 2, 3])
        #expect(flows[0].net == .dollars(1800))
        #expect(flows[0].savingsRate == 0.6)
        #expect(flows[1].income == .zero && flows[1].expenses == .zero)
        #expect(flows[2].expenses == .dollars(50))
    }

    @Test func percentChange() {
        #expect(CashFlow.change(from: .dollars(100), to: .dollars(88)) == -0.12)
        #expect(CashFlow.change(from: .zero, to: .dollars(10)) == nil)
        #expect(CashFlow.change(from: .dollars(-100), to: .dollars(-50)) == 0.5)
    }
}

@Suite("SpendingBreakdown")
struct SpendingBreakdownTests {
    let interval = YearMonth(year: 2026, month: 3).interval(in: TestCalendar.utc)
    let day = TestCalendar.date(2026, 3, 3)

    @Test("Largest category first with shares summing to 1")
    func byCategory() {
        let snapshot = Fixture.snapshot(transactions: [
            Fixture.expense(.dollars(60), .food, on: day),
            Fixture.expense(.dollars(15), .food, on: day),
            Fixture.expense(.dollars(25), .transport, on: day),
            Fixture.income(.dollars(999), on: day),
        ])
        let result = SpendingBreakdown.byCategory(in: snapshot, interval: interval)
        #expect(result.map(\.categoryID) == [.food, .transport])
        #expect(result[0].amount == .dollars(75))
        #expect(result[0].transactionCount == 2)
        #expect(result.map(\.share).reduce(0, +) == 1)
    }

    @Test("Categories beyond the limit fold into Other")
    func foldsTail() {
        let categories: [CategoryID] = [.food, .shopping, .transport, .travel, .health]
        let snapshot = Fixture.snapshot(transactions: categories.enumerated().map { index, category in
            Fixture.expense(.dollars(Double(100 - index * 10)), category, on: day)
        })
        let result = SpendingBreakdown.byCategory(in: snapshot, interval: interval, limit: 3)
        #expect(result.count == 3)
        #expect(result.last?.categoryID == .otherExpense)
        #expect(result.last?.amount == .dollars(210))
    }

    @Test("Year series has 12 monthly buckets")
    func yearSeries() {
        let snapshot = Fixture.snapshot(transactions: [Fixture.expense(.dollars(10), on: day)])
        let series = SpendingBreakdown.series(in: snapshot, period: .year, now: day, calendar: TestCalendar.utc)
        #expect(series.count == 12)
        #expect(series[2].amount == .dollars(10))
    }
}
