public import DesignSystem
public import Domain
public import FlowCore
public import Foundation
public import LedgerUI
public import Observation

/// Add / edit a transaction (screens 8 and 9).
@MainActor
@Observable
public final class TransactionEditorModel {
    public var kind: TransactionKind {
        didSet {
            // A "Salary" category makes no sense on an expense: clear it when the type flips.
            if let categoryID, categoryID.category.kind != kind {
                self.categoryID = nil
            }
        }
    }

    public var keypad = KeypadInput()
    public var categoryID: CategoryID?
    public var accountID: UUID?
    public var merchant = ""
    public var note = ""
    public var date: Date
    public private(set) var accounts: [Account] = []
    public private(set) var currency = CurrencyFormat.usd
    public private(set) var isLoaded = false
    public private(set) var isSaving = false
    public var errorMessage: String?

    private let context: LedgerContext
    private let editingID: UUID?
    private let preferredAccountID: UUID?
    private var existing: LedgerTransaction?
    private var history: [(merchant: String, category: CategoryID, kind: TransactionKind)] = []

    public init(context: LedgerContext, kind: TransactionKind, editing: UUID? = nil, accountID: UUID? = nil) {
        self.context = context
        self.kind = kind
        editingID = editing
        preferredAccountID = accountID
        date = context.now()
    }

    public var isEditing: Bool {
        editingID != nil
    }

    public var title: String {
        isEditing ? "Edit Transaction" : (kind == .expense ? "Add Expense" : "Add Income")
    }

    public func load() async {
        guard !isLoaded else { return }
        let snapshot = await context.repository.currentSnapshot()
        accounts = snapshot.accounts
        currency = snapshot.currency
        keypad = KeypadInput(maxFractionDigits: currency.fractionDigits)
        history = Self.merchantHistory(snapshot.transactions)
        if let editingID, let transaction = snapshot.transactions.first(where: { $0.id == editingID }) {
            existing = transaction
            kind = transaction.kind
            keypad = KeypadInput(
                text: "\(transaction.amount.decimalValue(fractionDigits: currency.fractionDigits))",
                maxFractionDigits: currency.fractionDigits
            )
            categoryID = transaction.categoryID
            accountID = transaction.accountID
            merchant = transaction.merchant
            note = transaction.note
            date = transaction.date
        } else {
            accountID = preferredAccountID ?? snapshot.accounts.first { !$0.kind.isLiability }?.id ?? snapshot.accounts.first?.id
        }
        isLoaded = true
    }

    public var amount: Money? {
        currency.parse(keypadInput: keypad.text)
    }

    public var draft: TransactionDraft {
        TransactionDraft(
            kind: kind, amount: amount, categoryID: categoryID, accountID: accountID,
            merchant: merchant, note: note, date: date
        )
    }

    public var canSave: Bool {
        draft.isValid && !isSaving
    }

    /// Up to three past merchants matching what's typed, most frequent first. Picking one also picks
    /// the category last used with it — the fastest path for repeat purchases.
    public var merchantSuggestions: [(merchant: String, category: CategoryID)] {
        let typed = merchant.trimmingCharacters(in: .whitespaces)
        guard typed.count >= 1 else { return [] }
        return history
            .filter { $0.kind == kind && $0.merchant.localizedCaseInsensitiveContains(typed) && $0.merchant != typed }
            .prefix(3)
            .map { ($0.merchant, $0.category) }
    }

    public func applySuggestion(merchant: String, category: CategoryID) {
        self.merchant = merchant
        if categoryID == nil {
            categoryID = category
        }
    }

    public func save() async -> Bool {
        guard canSave else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            let transaction = try draft.makeTransaction(existing: existing, now: context.now())
            try await context.repository.perform(.saveTransaction(transaction))
            return true
        } catch let problem as TransactionDraft.Problem {
            errorMessage = Self.message(for: problem)
        } catch {
            errorMessage = error.localizedDescription
        }
        return false
    }

    public func delete() async -> Bool {
        guard let editingID else { return false }
        do {
            try await context.repository.perform(.deleteTransaction(id: editingID))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    static func message(for problem: TransactionDraft.Problem) -> String {
        switch problem {
        case .missingAmount: "Enter an amount."
        case .missingCategory: "Choose a category."
        case .missingAccount: "Choose an account."
        case .amountTooLarge: "That amount is too large."
        }
    }

    static func merchantHistory(_ transactions: [LedgerTransaction]) -> [(merchant: String, category: CategoryID, kind: TransactionKind)] {
        var counts: [String: (count: Int, category: CategoryID, kind: TransactionKind)] = [:]
        // Newest first, so the stored category is the most recent one used with that merchant.
        for transaction in transactions where !transaction.merchant.isEmpty {
            if let entry = counts[transaction.merchant] {
                counts[transaction.merchant]?.count = entry.count + 1
            } else {
                counts[transaction.merchant] = (1, transaction.categoryID, transaction.kind)
            }
        }
        return counts
            .sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }
            .map { ($0.key, $0.value.category, $0.value.kind) }
    }
}
