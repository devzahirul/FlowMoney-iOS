import Domain
import FlowCore
import Foundation
import LedgerData
import PostgREST
@testable import SupabaseBackend
import Testing
import TestSupport

@Suite("Supabase wire format")
struct RowMappingTests {
    let encoder = PostgrestClient.Configuration.jsonEncoder
    let decoder = PostgrestClient.Configuration.jsonDecoder
    let date = TestCalendar.date(2026, 3, 10)

    func keys(of value: some Encodable) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any]
        return Set(object?.keys ?? [:].keys)
    }

    @Test("Transaction JSON keys match the SQL columns exactly (no user_id — the server defaults it)")
    func transactionColumns() throws {
        let row = TransactionRow(Fixture.expense(.dollars(5.2), on: date))
        #expect(try keys(of: row) == [
            "id", "account_id", "kind", "amount", "category_id", "merchant", "note", "occurred_at",
            "recurring_rule_id", "created_at", "updated_at", "deleted_at",
        ])
    }

    @Test("Every row type round-trips through JSON without loss")
    func roundTrips() throws {
        let goal = Fixture.goal(target: .dollars(5000), targetDate: date, monthly: .dollars(300))
        let transaction = Fixture.expense(.dollars(5.2), .food, on: date, merchant: "Café ☕️", note: "with \"quotes\"")
        let rule = Fixture.rule(start: date)
        let account = Account(
            name: "Card",
            kind: .creditCard,
            lastFour: "4821",
            openingBalance: .dollars(-120),
            createdAt: date,
            updatedAt: date
        )

        #expect(try decoder.decode(TransactionRow.self, from: encoder.encode(TransactionRow(transaction))).model == transaction)
        #expect(try decoder.decode(GoalRow.self, from: encoder.encode(GoalRow(goal))).model == goal)
        #expect(try decoder.decode(RecurringRuleRow.self, from: encoder.encode(RecurringRuleRow(rule))).model == rule)
        #expect(try decoder.decode(AccountRow.self, from: encoder.encode(AccountRow(account))).model == account)
    }

    @Test("Decodes PostgREST's microsecond timestamps and bigint amounts")
    func decodesServerPayload() throws {
        let json = """
        {"id":"6f1d2a52-8b5f-4a5e-9c1e-2d7a4b3c9e10","account_id":"22222222-2222-4222-8222-222222222222",
         "kind":"income","amount":320000,"category_id":"salary","merchant":"Acme","note":"",
         "occurred_at":"2026-03-01T09:00:00+00:00","recurring_rule_id":null,
         "created_at":"2026-03-01T09:00:00.123456+00:00","updated_at":"2026-03-01T09:00:01.654321+00:00","deleted_at":null}
        """
        let model = try decoder.decode(TransactionRow.self, from: Data(json.utf8)).model
        #expect(model.amount == .dollars(3200))
        #expect(model.kind == .income)
        #expect(model.signedAmount == .dollars(3200))
    }

    @Test("Unknown enum values from a newer app version degrade gracefully")
    func unknownValues() throws {
        let json = """
        {"id":"6f1d2a52-8b5f-4a5e-9c1e-2d7a4b3c9e10","name":"Crypto","kind":"crypto_wallet","institution":"",
         "last_four":null,"opening_balance":0,"sort_order":0,
         "created_at":"2026-03-01T09:00:00+00:00","updated_at":"2026-03-01T09:00:00+00:00","deleted_at":null}
        """
        #expect(try decoder.decode(AccountRow.self, from: Data(json.utf8)).model.kind == .checking)
    }
}

@Suite("Supabase error mapping")
struct ErrorMappingTests {
    @Test func connectivityIsOffline() {
        #expect(SupabaseLedgerService.map(URLError(.notConnectedToInternet)) == .offline)
        #expect(SupabaseLedgerService.map(URLError(.timedOut)) == .offline)
    }

    @Test func expiredJWTIsUnauthorized() {
        #expect(SupabaseLedgerService.map(PostgrestError(code: "PGRST303", message: "JWT expired")) == .unauthorized)
    }

    @Test func constraintViolationIsServerError() {
        let error = PostgrestError(code: "23514", message: "violates check constraint")
        #expect(SupabaseLedgerService.map(error) == .server("violates check constraint"))
    }

    @Test func authConnectivityIsOffline() {
        #expect(SupabaseAuthService.map(URLError(.networkConnectionLost)) == .offline)
    }

    @Test("Configuration is absent when the xcconfig placeholders weren't filled in")
    func configuration() {
        #expect(SupabaseConfiguration(infoDictionary: ["FlowMoneySupabaseHost": "", "FlowMoneySupabaseKey": "x"]) == nil)
        #expect(SupabaseConfiguration(infoDictionary: ["FlowMoneySupabaseHost": "$(SUPABASE_HOST)", "FlowMoneySupabaseKey": "x"]) == nil)
        let config = SupabaseConfiguration(infoDictionary: [
            "FlowMoneySupabaseHost": "abc.supabase.co",
            "FlowMoneySupabaseKey": "sb_publishable_x",
        ])
        #expect(config?.url.absoluteString == "https://abc.supabase.co")
    }
}
