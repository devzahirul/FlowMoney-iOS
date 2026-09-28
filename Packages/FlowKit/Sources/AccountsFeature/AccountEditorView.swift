public import Domain
public import FlowCore
public import Foundation
public import LedgerUI
public import Observation
public import SwiftUI
import DesignSystem

@MainActor
@Observable
public final class AccountEditorModel {
    public var name = ""
    public var kind = AccountKind.checking
    public var institution = ""
    public var lastFour = ""
    /// Signed decimal text, e.g. "-1260.50" for a card balance.
    public var openingBalance = ""
    public private(set) var isSaving = false
    public var errorMessage: String?
    public private(set) var currency = CurrencyFormat.usd

    private let context: LedgerContext
    private let editingID: UUID?
    private var existing: Account?
    private var nextSortOrder = 0

    public init(context: LedgerContext, editing: UUID?) {
        self.context = context
        editingID = editing
    }

    public var isEditing: Bool {
        editingID != nil
    }

    public func load() async {
        let snapshot = await context.repository.currentSnapshot()
        currency = snapshot.currency
        nextSortOrder = (snapshot.accounts.map(\.sortOrder).max() ?? -1) + 1
        guard let editingID, let account = snapshot.accountsByID[editingID] else { return }
        existing = account
        name = account.name
        kind = account.kind
        institution = account.institution
        lastFour = account.lastFour ?? ""
        openingBalance = "\(account.openingBalance.decimalValue(fractionDigits: currency.fractionDigits))"
    }

    /// Parsed opening balance; debts are stored negative even if the user types a positive number.
    public var parsedOpening: Money? {
        let trimmed = openingBalance.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return .zero
        }
        guard let decimal = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let money = Money(decimal, fractionDigits: currency.fractionDigits)
        return kind.isLiability ? -money.magnitude : money
    }

    public var lastFourIsValid: Bool {
        lastFour.isEmpty || lastFour.wholeMatch(of: #/[0-9]{4}/#) != nil
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && parsedOpening != nil && lastFourIsValid && !isSaving
    }

    public func save() async -> Bool {
        guard canSave, let opening = parsedOpening else { return false }
        isSaving = true
        defer { isSaving = false }
        let account = Account(
            id: existing?.id ?? UUID(),
            name: name,
            kind: kind,
            institution: institution.trimmingCharacters(in: .whitespaces),
            lastFour: lastFour.isEmpty ? nil : lastFour,
            openingBalance: opening,
            sortOrder: existing?.sortOrder ?? nextSortOrder,
            createdAt: existing?.createdAt ?? context.now()
        )
        do {
            try await context.repository.perform(.saveAccount(account))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

public struct AccountEditorView: View {
    @State private var model: AccountEditorModel
    @Environment(\.dismiss) private var dismiss

    public init(context: LedgerContext, editing: UUID?) {
        _model = State(initialValue: AccountEditorModel(context: context, editing: editing))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Chase Checking)", text: $model.name)
                        .accessibilityIdentifier("account.name")
                    Picker("Type", selection: $model.kind) {
                        ForEach(AccountKind.allCases, id: \.self) { kind in
                            Label(kind.title, systemImage: kind.symbol).tag(kind)
                        }
                    }
                    TextField("Bank or institution", text: $model.institution)
                }
                Section {
                    HStack {
                        Text(model.kind.isLiability ? "Amount owed" : "Current balance")
                        Spacer()
                        TextField("0.00", text: $model.openingBalance)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("account.balance")
                    }
                    if model.kind == .creditCard || model.kind == .checking {
                        TextField("Last 4 digits (optional)", text: $model.lastFour)
                            .keyboardType(.numberPad)
                    }
                } footer: {
                    Text(model.kind.isLiability
                        ? "Enter what you owe today; it's tracked as a negative balance."
                        : "Your balance today. Future transactions adjust it automatically.")
                }
                if !model.lastFourIsValid {
                    Text("Last 4 digits must be exactly four numbers.").foregroundStyle(Theme.expense)
                }
                if let error = model.errorMessage {
                    Section { ErrorBanner(error) }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Account" : "Add Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.save() {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("account.save")
                }
            }
            .task { await model.load() }
        }
    }
}
