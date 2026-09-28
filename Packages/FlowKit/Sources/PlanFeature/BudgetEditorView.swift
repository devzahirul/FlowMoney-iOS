public import Domain
public import FlowCore
public import Foundation
public import LedgerUI
public import Observation
public import SwiftUI
import DesignSystem

@MainActor
@Observable
public final class BudgetEditorModel {
    public var categoryID: CategoryID?
    public var limitText = ""
    public private(set) var availableCategories: [Domain.Category] = []
    /// Average monthly spend in the chosen category over the last 3 months — a sensible starting limit.
    public private(set) var suggestedLimit: Money?
    public private(set) var currency = CurrencyFormat.usd
    public var errorMessage: String?

    private let context: LedgerContext
    private let editingID: UUID?
    private var ownerID = UUID()
    private var snapshot: LedgerSnapshot?

    public init(context: LedgerContext, editing: UUID?) {
        self.context = context
        editingID = editing
    }

    public var isEditing: Bool {
        editingID != nil
    }

    public var limit: Money? {
        currency.parse(userInput: limitText).flatMap { $0.minorUnits > 0 ? $0 : nil }
    }

    public var canSave: Bool {
        categoryID != nil && limit != nil
    }

    public func load() async {
        let snapshot = await context.repository.currentSnapshot()
        self.snapshot = snapshot
        currency = snapshot.currency
        ownerID = snapshot.profile.id
        let budgeted = Set(snapshot.budgets.map(\.categoryID))
        if let editingID, let budget = snapshot.budgets.first(where: { $0.id == editingID }) {
            categoryID = budget.categoryID
            limitText = currency.editingText(budget.limit)
            availableCategories = [budget.categoryID.category]
        } else {
            availableCategories = CategoryCatalog.expense.filter { !budgeted.contains($0.id) }
        }
        updateSuggestion()
    }

    public func updateSuggestion() {
        guard let snapshot, let categoryID else {
            suggestedLimit = nil
            return
        }
        let months = context.currentMonth.previous.trailing(3)
        let total = months.sum { month in
            snapshot.transactions(in: month, calendar: context.calendar)
                .filter { $0.kind == .expense && $0.categoryID == categoryID }
                .sum(\.amount)
        }
        suggestedLimit = total.isZero ? nil : Money(minorUnits: total.minorUnits / Int64(months.count))
    }

    public func save() async -> Bool {
        guard let categoryID, let limit else { return false }
        let budget = Budget(
            id: editingID ?? Budget.id(for: categoryID, owner: ownerID),
            categoryID: categoryID,
            limit: limit,
            createdAt: context.now()
        )
        do {
            try await context.repository.perform(.saveBudget(budget))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

public struct BudgetEditorView: View {
    @State private var model: BudgetEditorModel
    @Environment(\.dismiss) private var dismiss

    public init(context: LedgerContext, editing: UUID?) {
        _model = State(initialValue: BudgetEditorModel(context: context, editing: editing))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Category") {
                    if model.availableCategories.isEmpty, !model.isEditing {
                        Text("Every category already has a budget.").foregroundStyle(.secondary)
                    }
                    Picker("Category", selection: $model.categoryID) {
                        Text("Choose…").tag(CategoryID?.none)
                        ForEach(model.availableCategories) { category in
                            Label(category.name, systemImage: category.symbol).tag(Optional(category.id))
                        }
                    }
                    .disabled(model.isEditing)
                    .accessibilityIdentifier("budget.category")
                }
                Section {
                    MoneyField("Monthly limit", text: $model.limitText)
                        .accessibilityIdentifier("budget.limit")
                } footer: {
                    if let suggested = model.suggestedLimit {
                        Button {
                            model.limitText = model.currency.editingText(suggested)
                        } label: {
                            Text("You've averaged \(model.currency.string(suggested)) a month here. Use that")
                        }
                        .font(.footnote)
                    }
                }
                if let error = model.errorMessage {
                    Section { ErrorBanner(error) }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Budget" : "New Budget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task {
                        if await model.save() {
                            dismiss()
                        }
                    } }
                    .disabled(!model.canSave)
                    .accessibilityIdentifier("budget.save")
                }
            }
            .onChange(of: model.categoryID) { model.updateSuggestion() }
            .task { await model.load() }
        }
        .environment(\.currency, model.currency)
        .presentationDetents([.medium, .large])
    }
}
