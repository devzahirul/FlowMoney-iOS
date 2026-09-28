@testable import ActivityFeature
@testable import AuthFeature
import DesignSystem
import Domain
import FlowCore
import Foundation
@testable import HomeFeature
import LedgerData
import LedgerUI
@testable import PlanFeature
import Routing
import Testing
import TestSupport

/// Builds a real repository (in-memory disk, no network): view models are tested against the same store
/// the app uses, so a test proves the whole slice — UI state → mutation → snapshot — not a mock's opinion.
@MainActor
func makeContext(transactions: [LedgerTransaction] = [], budgets: [Budget] = []) async -> LedgerContext {
    var state = LedgerState(profile: Fixture.profile())
    state.accounts[Fixture.checkingID] = Fixture.account(opening: .dollars(1000))
    for transaction in transactions {
        state.transactions[transaction.id] = transaction
    }
    for budget in budgets {
        state.budgets[budget.id] = budget
    }
    let initialState = state
    let repository = await LocalLedgerRepository(
        initialState: initialState,
        persistence: InMemoryLedgerPersistence(),
        remote: nil,
        calendar: TestCalendar.utc,
        now: { TestCalendar.date(2026, 3, 15) }
    )
    return LedgerContext(repository: repository, calendar: TestCalendar.utc, now: { TestCalendar.date(2026, 3, 15) })
}

@Suite("Auth view models")
@MainActor
struct AuthModelTests {
    let session = AuthSession(userID: UUID(), email: "alex@email.com", displayName: "Alex")

    @Test("Sign-in button is disabled until the email looks valid and a password is entered")
    func loginValidation() {
        let model = LoginModel(auth: FakeAuthService(), actions: AuthActions(signedIn: { _ in }, startDemo: {}))
        #expect(!model.canSubmit)
        model.email = "alex@email"
        model.password = "secret"
        #expect(!model.canSubmit)
        model.email = "alex@email.com"
        #expect(model.canSubmit)
    }

    @Test("Wrong password shows a friendly error and clears the password field")
    func loginFailure() async {
        let model = LoginModel(auth: FakeAuthService(), actions: AuthActions(signedIn: { _ in }, startDemo: {}))
        model.email = "alex@email.com"
        model.password = "wrong"
        await model.submit()
        #expect(model.errorMessage == "That email and password don't match.")
        #expect(model.password.isEmpty)
    }

    @Test("Successful sign-in hands the session to the app shell")
    func loginSuccess() async {
        let auth = FakeAuthService()
        await auth.script(signIn: .success(session))
        var received: AuthSession?
        let model = LoginModel(auth: auth, actions: AuthActions(signedIn: { received = $0 }, startDemo: {}))
        model.email = "alex@email.com"
        model.password = "right"
        await model.submit()
        #expect(received == session)
        #expect(model.errorMessage == nil)
    }

    @Test("Sign-up that needs email confirmation moves to the check-your-inbox state")
    func signUpConfirmation() async {
        let auth = FakeAuthService()
        await auth.script(signUp: .success(.confirmationRequired(email: "alex@email.com")))
        let model = SignUpModel(auth: auth, actions: AuthActions(signedIn: { _ in }, startDemo: {}))
        model.name = "Alex"
        model.email = "alex@email.com"
        model.password = "longenough1"
        #expect(!model.canSubmit, "password lacks a special character")
        model.password = "longenough1!"
        #expect(!model.canSubmit, "terms not accepted")
        model.acceptedTerms = true
        await model.submit()
        #expect(model.phase == .awaitingConfirmation(email: "alex@email.com"))
    }
}

@Suite("Transaction editor")
@MainActor
struct TransactionEditorTests {
    @Test("Loads with the first account selected and saves a valid expense")
    func savesExpense() async {
        let context = await makeContext()
        let model = TransactionEditorModel(context: context, kind: .expense)
        await model.load()
        #expect(model.accountID == Fixture.checkingID)
        #expect(!model.canSave)

        for key: KeypadInput.Key in [.digit(1), .digit(2), .decimal, .digit(5)] {
            model.keypad.press(key)
        }
        model.categoryID = .food
        model.merchant = "  Starbucks  "
        #expect(model.canSave)
        #expect(await model.save())

        let saved = await context.repository.currentSnapshot().transactions.first
        #expect(saved?.amount == .dollars(12.5))
        #expect(saved?.merchant == "Starbucks")
    }

    @Test("Switching to income clears an expense-only category")
    func kindFlipClearsCategory() async {
        let model = await TransactionEditorModel(context: makeContext(), kind: .expense)
        model.categoryID = .food
        model.kind = .income
        #expect(model.categoryID == nil)
        model.categoryID = .salary
        model.kind = .income
        #expect(model.categoryID == .salary)
    }

    @Test("Editing pre-fills the form and keeps the same ID")
    func editing() async {
        let existing = Fixture.expense(.dollars(8.4), .transport, on: TestCalendar.date(2026, 3, 10), merchant: "Uber")
        let context = await makeContext(transactions: [existing])
        let model = TransactionEditorModel(context: context, kind: .expense, editing: existing.id)
        await model.load()
        #expect(model.keypad.text == "8.4")
        #expect(model.merchant == "Uber")
        model.keypad.press(.digit(5))
        #expect(await model.save())
        let snapshot = await context.repository.currentSnapshot()
        #expect(snapshot.transactions.count == 1)
        #expect(snapshot.transactions.first?.amount == .dollars(8.45))
    }

    @Test("Merchant suggestions come from history, most frequent first, and pick the category")
    func suggestions() async {
        let day = TestCalendar.date(2026, 3, 10)
        let context = await makeContext(transactions: [
            Fixture.expense(.dollars(5), .food, on: day, merchant: "Starbucks"),
            Fixture.expense(.dollars(5), .food, on: day, merchant: "Starbucks"),
            Fixture.expense(.dollars(9), .groceries, on: day, merchant: "Star Market"),
        ])
        let model = TransactionEditorModel(context: context, kind: .expense)
        await model.load()
        model.merchant = "sta"
        #expect(model.merchantSuggestions.map(\.merchant) == ["Starbucks", "Star Market"])
        model.applySuggestion(merchant: "Star Market", category: .groceries)
        #expect(model.categoryID == .groceries)
    }
}

@Suite("Keypad input")
struct KeypadInputTests {
    func typing(_ keys: [KeypadInput.Key], digits: Int = 2) -> String {
        var input = KeypadInput(maxFractionDigits: digits)
        keys.forEach { input.press($0) }
        return input.text
    }

    @Test func rules() {
        #expect(typing([.digit(0), .digit(5)]) == "5", "no leading zero")
        #expect(typing([.decimal, .digit(5)]) == "0.5", "leading decimal gets a zero")
        #expect(typing([.digit(1), .decimal, .decimal, .digit(2)]) == "1.2", "one decimal point")
        #expect(typing([.digit(1), .decimal, .digit(2), .digit(3), .digit(4)]) == "1.23", "max two decimals")
        #expect(typing([.digit(9), .backspace, .backspace]).isEmpty)
        #expect(typing([.digit(1), .decimal, .digit(2)], digits: 0) == "12", "JPY has no decimals")
        #expect(typing(Array(repeating: .digit(9), count: 12)).count == KeypadInput.maxIntegerDigits)
    }
}

@Suite("Home & budgets")
@MainActor
struct HomeAndBudgetTests {
    @Test("Dashboard totals come from the ledger")
    func homeState() async {
        let context = await makeContext(transactions: [
            Fixture.income(.dollars(3000), on: TestCalendar.date(2026, 3, 1)),
            Fixture.expense(.dollars(120), on: TestCalendar.date(2026, 3, 5)),
            Fixture.expense(.dollars(999), on: TestCalendar.date(2026, 2, 5)),
        ])
        let snapshot = await context.repository.currentSnapshot()
        let state = HomeViewModel.makeState(snapshot, now: context.now(), calendar: context.calendar)
        #expect(state.totalBalance == .dollars(2881))
        #expect(state.income == .dollars(3000))
        #expect(state.expenses == .dollars(120))
        #expect(state.recent.count == 3)
        #expect(state.firstName == "Alex")
    }

    @Test("Budget editor suggests the 3-month average and uses the deterministic per-category ID")
    func budgetEditor() async {
        let context = await makeContext(transactions: [
            Fixture.expense(.dollars(300), .food, on: TestCalendar.date(2026, 2, 3)),
            Fixture.expense(.dollars(150), .food, on: TestCalendar.date(2026, 1, 3)),
            Fixture.expense(.dollars(150), .food, on: TestCalendar.date(2025, 12, 3)),
        ])
        let model = BudgetEditorModel(context: context, editing: nil)
        await model.load()
        model.categoryID = .food
        model.updateSuggestion()
        #expect(model.suggestedLimit == .dollars(200))
        model.limitText = "250"
        #expect(await model.save())
        let budget = await context.repository.currentSnapshot().budgets.first
        #expect(budget?.id == Budget.id(for: .food, owner: Fixture.userID))
        #expect(budget?.limit == .dollars(250))
    }

    @Test("Activity search filters as the query changes")
    func activitySearch() async {
        let day = TestCalendar.date(2026, 3, 10)
        let context = await makeContext(transactions: [
            Fixture.expense(.dollars(5), .food, on: day, merchant: "Starbucks"),
            Fixture.expense(.dollars(20), .transport, on: day, merchant: "Uber"),
        ])
        let model = TransactionsViewModel(context: context)
        await model.update(with: context.repository.currentSnapshot())
        #expect(model.sections.first?.transactions.count == 2)
        model.query = "uber"
        model.applyQuery()
        #expect(model.sections.first?.transactions.map(\.merchant) == ["Uber"])
        model.query = "nothing"
        model.applyQuery()
        #expect(model.isEmpty)
    }
}

@Suite("Router")
@MainActor
struct RouterTests {
    @Test("Deep links open the same screens a tap would")
    func deepLinks() throws {
        let router = Router()
        #expect(try router.open(#require(URL(string: "flowmoney://add-expense"))))
        #expect(router.sheet == .transactionEditor(kind: .expense))

        let id = UUID()
        #expect(try router.open(#require(URL(string: "flowmoney://transaction/\(id.uuidString)"))))
        #expect(router.selectedTab == .activity)
        #expect(router.paths[.activity] == [.transaction(id)])

        #expect(try !router.open(#require(URL(string: "https://example.com"))))
        #expect(try !router.open(#require(URL(string: "flowmoney://unknown"))))
    }

    @Test("Re-selecting the current tab pops to root")
    func popToRoot() {
        let router = Router()
        router.push(.accounts)
        router.push(.budgets)
        router.select(.home)
        #expect(router.paths[.home]?.isEmpty == true)
    }
}
