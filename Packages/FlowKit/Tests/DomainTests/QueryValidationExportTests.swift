@testable import Domain
import FlowCore
import Foundation
import Testing
import TestSupport

@Suite("TransactionQuery")
struct TransactionQueryTests {
    let day = TestCalendar.date(2026, 3, 3)

    var snapshot: LedgerSnapshot {
        Fixture.snapshot(transactions: [
            Fixture.expense(.dollars(5.20), .food, on: day, merchant: "Starbucks"),
            Fixture.expense(.dollars(4.80), .food, on: day, merchant: "Blue Bottle Coffee"),
            Fixture.expense(.dollars(20), .transport, on: day, merchant: "Uber", note: "Airport café run"),
            Fixture.income(.dollars(3200), on: day, merchant: "Acme Payroll"),
        ])
    }

    @Test(arguments: [
        ("coffee", ["Blue Bottle Coffee"]),
        ("CAFE", ["Uber"]), // diacritic-insensitive match on the note
        ("food star", ["Starbucks"]), // every term must match
        ("5.20", ["Starbucks"]), // amount search
        ("checking", ["Starbucks", "Blue Bottle Coffee", "Uber", "Acme Payroll"]), // account name
        ("zzz", []),
    ])
    func search(query: String, expected: [String]) {
        #expect(Set(TransactionQuery.search(query, in: snapshot).map(\.merchant)) == Set(expected))
    }

    @Test func filterByKind() {
        #expect(TransactionQuery.search("", filter: .income, in: snapshot).map(\.merchant) == ["Acme Payroll"])
        #expect(TransactionQuery.search("", filter: .expense, in: snapshot).count == 3)
    }

    @Test("Groups consecutive days with a net total")
    func grouping() {
        let snapshot = Fixture.snapshot(transactions: [
            Fixture.income(.dollars(100), on: TestCalendar.date(2026, 3, 3, hour: 9)),
            Fixture.expense(.dollars(30), on: TestCalendar.date(2026, 3, 3, hour: 18)),
            Fixture.expense(.dollars(10), on: TestCalendar.date(2026, 3, 1)),
        ])
        let sections = TransactionQuery.groupedByDay(snapshot.transactions, calendar: TestCalendar.utc)
        #expect(sections.count == 2)
        #expect(sections[0].net == .dollars(70))
        #expect(sections[1].transactions.count == 1)
    }
}

@Suite("Validation")
struct ValidationTests {
    @Test(arguments: [
        ("alex@email.com", true),
        (" alex@email.com ", true),
        ("alex@email", false),
        ("alex email@x.com", false),
        ("", false),
    ])
    func email(address: String, valid: Bool) {
        #expect(EmailAddress.isValid(address) == valid)
    }

    @Test(arguments: [
        ("short1!", false),
        ("longenough", false),
        ("longenough1", false),
        ("longenough1!", true),
    ])
    func password(password: String, valid: Bool) {
        #expect(PasswordPolicy.isValid(password) == valid)
    }

    @Test("Draft reports the first missing field, in form order")
    func draftProblems() {
        var draft = TransactionDraft(kind: .expense, date: .now)
        #expect(draft.problem == .missingAmount)
        draft.amount = .dollars(5)
        #expect(draft.problem == .missingCategory)
        draft.categoryID = .food
        #expect(draft.problem == .missingAccount)
        draft.accountID = UUID()
        #expect(draft.isValid)
        draft.amount = Money(minorUnits: TransactionDraft.maximumAmount.minorUnits + 1)
        #expect(draft.problem == .amountTooLarge)
    }

    @Test("Editing keeps identity and creation date, trims text")
    func editing() throws {
        let original = Fixture.expense(.dollars(5), on: TestCalendar.date(2026, 3, 1), merchant: "Old")
        var draft = TransactionDraft(editing: original)
        draft.merchant = "  New  "
        let saved = try draft.makeTransaction(existing: original, now: TestCalendar.date(2026, 3, 2))
        #expect(saved.id == original.id)
        #expect(saved.createdAt == original.createdAt)
        #expect(saved.merchant == "New")
        #expect(saved.updatedAt == TestCalendar.date(2026, 3, 2))
    }
}

@Suite("LedgerCSV")
struct LedgerCSVTests {
    @Test("RFC 4180 quoting and formula-injection defence")
    func escaping() {
        #expect(LedgerCSV.escape("plain") == "plain")
        #expect(LedgerCSV.escape("a,b") == "\"a,b\"")
        #expect(LedgerCSV.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(LedgerCSV.escape("=HYPERLINK(\"x\")") == "\"'=HYPERLINK(\"\"x\"\")\"")
        #expect(LedgerCSV.escape("-5.20") == "-5.20")
    }

    @Test("Rows carry signed amounts and CRLF line endings")
    func rows() {
        let snapshot = Fixture.snapshot(transactions: [Fixture.expense(
            .dollars(5.2),
            on: TestCalendar.date(2026, 3, 3),
            merchant: "Café, Inc"
        )])
        let csv = LedgerCSV.make(snapshot.transactions, snapshot: snapshot, calendar: TestCalendar.utc)
        let lines = csv.components(separatedBy: "\r\n")
        #expect(lines[0] == "Date,Type,Merchant,Category,Account,Amount,Currency,Note")
        #expect(lines[1] == "2026-03-03,Expense,\"Café, Inc\",Food & Drink,Checking,-5.20,USD,")
    }
}

@Suite("DemoLedger")
struct DemoLedgerTests {
    @Test("Deterministic: the same inputs give identical data")
    func deterministic() {
        let now = TestCalendar.date(2026, 3, 15)
        let first = DemoLedger.make(now: now, calendar: TestCalendar.utc)
        let second = DemoLedger.make(now: now, calendar: TestCalendar.utc)
        #expect(first.transactions == second.transactions)
        #expect(first.transactions.count > 150)
    }

    @Test("Nothing is dated in the future and every row belongs to a real account")
    func integrity() {
        let now = TestCalendar.date(2026, 3, 15)
        let content = DemoLedger.make(now: now, calendar: TestCalendar.utc)
        let accountIDs = Set(content.accounts.map(\.id))
        #expect(content.transactions.allSatisfy { $0.date <= now && accountIDs.contains($0.accountID) })
        #expect(Set(content.transactions.map(\.id)).count == content.transactions.count)
    }
}
