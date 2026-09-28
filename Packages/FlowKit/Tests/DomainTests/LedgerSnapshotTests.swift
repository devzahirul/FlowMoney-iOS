@testable import Domain
import FlowCore
import Foundation
import Testing
import TestSupport

@Suite("LedgerSnapshot")
struct LedgerSnapshotTests {
    let march = TestCalendar.date(2026, 3, 10)

    @Test("Balances = opening balance + income − spending, per account")
    func balances() {
        let savings = Fixture.account(id: UUID(), name: "Savings", kind: .savings, opening: .dollars(1000))
        let snapshot = Fixture.snapshot(
            accounts: [Fixture.account(opening: .dollars(100)), savings],
            transactions: [
                Fixture.income(.dollars(50), on: march),
                Fixture.expense(.dollars(30), on: march),
                Fixture.expense(.dollars(200), on: march, account: savings.id),
            ]
        )
        #expect(snapshot.balance(of: Fixture.checkingID) == .dollars(120))
        #expect(snapshot.balance(of: savings.id) == .dollars(800))
        #expect(snapshot.totalBalance == .dollars(920))
    }

    @Test("Tombstoned rows and orphans of deleted accounts are hidden")
    func hidesDeleted() {
        var deleted = Fixture.expense(.dollars(5), on: march)
        deleted.deletedAt = march
        var closed = Fixture.account(id: UUID(), name: "Closed")
        closed.deletedAt = march
        let orphan = Fixture.expense(.dollars(9), on: march, account: closed.id)
        let snapshot = Fixture.snapshot(accounts: [Fixture.account(), closed], transactions: [deleted, orphan])
        #expect(snapshot.transactions.isEmpty)
        #expect(snapshot.accounts.map(\.name) == ["Checking"])
    }

    @Test("Transactions are newest first and interval slicing is exact at boundaries")
    func intervalSlice() {
        let calendar = TestCalendar.utc
        let feb28 = TestCalendar.date(2026, 2, 28, hour: 23, minute: 59)
        let mar1 = TestCalendar.date(2026, 3, 1, hour: 0)
        let mar31 = TestCalendar.date(2026, 3, 31, hour: 23, minute: 59)
        let apr1 = TestCalendar.date(2026, 4, 1, hour: 0)
        let snapshot = Fixture.snapshot(transactions: [feb28, mar1, mar31, apr1].map { Fixture.expense(.dollars(1), on: $0) })
        #expect(snapshot.transactions.first?.date == apr1)
        let inMarch = snapshot.transactions(in: YearMonth(year: 2026, month: 3), calendar: calendar)
        #expect(inMarch.map(\.date) == [mar31, mar1])
    }

    @Test("Goal savings sum contributions, including withdrawals")
    func goalSavings() {
        let goal = Fixture.goal(target: .dollars(1000))
        let snapshot = Fixture.snapshot(
            goals: [goal],
            contributions: [
                Fixture.contribution(.dollars(300), to: goal.id, on: march),
                Fixture.contribution(.dollars(-50), to: goal.id, on: march),
            ]
        )
        #expect(snapshot.saved(toward: goal.id) == .dollars(250))
    }
}
