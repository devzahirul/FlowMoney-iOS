public import Domain
public import FlowCore
public import Foundation
public import LedgerUI
public import Observation
public import SwiftUI
import DesignSystem
import Routing

@MainActor
@Observable
final class RecurringListModel: LedgerObserving {
    struct Item: Identifiable, Equatable {
        let rule: RecurringRule
        let next: Date?
        var id: UUID {
            rule.id
        }
    }

    private(set) var items: [Item] = []
    private(set) var monthlyTotal = Money.zero
    private(set) var yearlyTotal = Money.zero
    private(set) var isLoaded = false
    var errorMessage: String?

    let context: LedgerContext
    var lastRevision: Int?
    let subscriptionsOnly: Bool

    init(context: LedgerContext, subscriptionsOnly: Bool) {
        self.context = context
        self.subscriptionsOnly = subscriptionsOnly
    }

    func update(with snapshot: LedgerSnapshot) {
        let now = context.now()
        items = snapshot.recurringRules
            .filter { !subscriptionsOnly || $0.isSubscription }
            .map { Item(rule: $0, next: $0.isPaused ? nil : $0.nextOccurrence(onOrAfter: now, calendar: context.calendar)) }
            .sorted { ($0.next ?? .distantFuture, $0.rule.name) < ($1.next ?? .distantFuture, $1.rule.name) }
        let active = items.map(\.rule).filter { !$0.isPaused && $0.kind == .expense }
        monthlyTotal = active.sum(\.monthlyEquivalent)
        yearlyTotal = monthlyTotal * 12
        isLoaded = true
    }

    func togglePause(_ rule: RecurringRule) async {
        var updated = rule
        updated.isPaused.toggle()
        await perform(.saveRecurringRule(updated))
    }

    func delete(_ rule: RecurringRule) async {
        await perform(.deleteRecurringRule(id: rule.id))
    }

    private func perform(_ mutation: LedgerMutation) async {
        do {
            try await context.repository.perform(mutation)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Screen 15 (subscriptions) and screen 21 (all recurring transactions) — one view, two filters.
public struct RecurringListView: View {
    @State private var model: RecurringListModel
    @Environment(Router.self) private var router

    public init(context: LedgerContext, subscriptionsOnly: Bool) {
        _model = State(initialValue: RecurringListModel(context: context, subscriptionsOnly: subscriptionsOnly))
    }

    public var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(model.subscriptionsOnly ? "Total monthly cost" : "Monthly bills").font(.subheadline).foregroundStyle(.secondary)
                    AmountText(model.monthlyTotal).font(.system(.title, design: .rounded, weight: .bold))
                    HStack(spacing: 4) {
                        AmountText(model.yearlyTotal)
                        Text("per year")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
            Section {
                ForEach(model.items) { item in
                    RecurringRow(item: item, now: model.context.now(), calendar: model.context.calendar)
                        .contentShape(.rect)
                        .onTapGesture { router.present(.recurringEditor(editing: item.id, subscription: item.rule.isSubscription)) }
                        .swipeActions {
                            Button("Delete", role: .destructive) { Task { await model.delete(item.rule) } }
                            Button(item.rule.isPaused ? "Resume" : "Pause") { Task { await model.togglePause(item.rule) } }
                                .tint(Theme.warning)
                        }
                        .accessibilityAddTraits(.isButton)
                }
            } footer: {
                if !model.items.isEmpty {
                    Text("Swipe to pause or delete. Auto-posted items are added to your transactions on their due date.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if model.isLoaded, model.items.isEmpty {
                ContentUnavailableView {
                    Label(model.subscriptionsOnly ? "No subscriptions" : "Nothing recurring", systemImage: "repeat")
                } description: {
                    Text("Track Netflix, rent, your salary — anything that repeats.")
                }
            }
        }
        .navigationTitle(model.subscriptionsOnly ? "Subscriptions" : "Recurring")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.present(.recurringEditor(subscription: model.subscriptionsOnly))
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(model.subscriptionsOnly ? "Add subscription" : "Add recurring item")
                .accessibilityIdentifier("recurring.add")
            }
        }
        .task { await model.observe() }
        .errorAlert($model.errorMessage)
    }
}

struct RecurringRow: View {
    let item: RecurringListModel.Item
    let now: Date
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 12) {
            MonogramBadge(item.rule.name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.rule.name).font(.body.weight(.medium))
                Group {
                    if item.rule.isPaused {
                        Text("Paused")
                    } else if let next = item.next {
                        Text("\(item.rule.frequency.title) · Next \(RelativeDay.phrase(for: next, now: now, calendar: calendar))")
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(item.rule.kind == .income ? item.rule.amount : -item.rule.amount, style: .signed)
                .font(.body.weight(.semibold))
        }
        .opacity(item.rule.isPaused ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Editor

@MainActor
@Observable
public final class RecurringEditorModel {
    public var name = ""
    public var amountText = ""
    public var kind = TransactionKind.expense
    public var categoryID: CategoryID = .subscriptions
    public var accountID: UUID?
    public var frequency = RecurrenceFrequency.monthly
    public var startDate: Date
    public var isSubscription: Bool
    public var autoPost = true
    public private(set) var accounts: [Account] = []
    public private(set) var currency = CurrencyFormat.usd
    public var errorMessage: String?

    private let context: LedgerContext
    private let editingID: UUID?
    private var existing: RecurringRule?

    public init(context: LedgerContext, editing: UUID?, subscription: Bool) {
        self.context = context
        editingID = editing
        isSubscription = subscription
        startDate = context.now()
        if !subscription {
            categoryID = .bills
        }
    }

    public var isEditing: Bool {
        editingID != nil
    }

    public var amount: Money? {
        currency.parse(userInput: amountText).flatMap { $0.minorUnits > 0 ? $0 : nil }
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && amount != nil && accountID != nil
    }

    public func load() async {
        let snapshot = await context.repository.currentSnapshot()
        currency = snapshot.currency
        accounts = snapshot.accounts
        accountID = snapshot.accounts.first?.id
        guard let editingID, let rule = snapshot.recurringRules.first(where: { $0.id == editingID }) else { return }
        existing = rule
        name = rule.name
        amountText = currency.editingText(rule.amount)
        kind = rule.kind
        categoryID = rule.categoryID
        accountID = rule.accountID
        frequency = rule.frequency
        startDate = rule.startDate
        isSubscription = rule.isSubscription
        autoPost = rule.autoPost
    }

    public func save() async -> Bool {
        guard let amount, let accountID else { return false }
        let rule = RecurringRule(
            id: existing?.id ?? UUID(),
            name: name,
            kind: kind,
            amount: amount,
            categoryID: categoryID.category.kind == kind ? categoryID : (kind == .income ? .salary : .bills),
            accountID: accountID,
            frequency: frequency,
            startDate: startDate,
            isSubscription: isSubscription && kind == .expense,
            autoPost: autoPost,
            isPaused: existing?.isPaused ?? false,
            createdAt: existing?.createdAt ?? context.now()
        )
        do {
            try await context.repository.perform(.saveRecurringRule(rule))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

public struct RecurringEditorView: View {
    @State private var model: RecurringEditorModel
    @Environment(\.dismiss) private var dismiss

    public init(context: LedgerContext, editing: UUID?, subscription: Bool) {
        _model = State(initialValue: RecurringEditorModel(context: context, editing: editing, subscription: subscription))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $model.kind) {
                        Text("Expense").tag(TransactionKind.expense)
                        Text("Income").tag(TransactionKind.income)
                    }
                    .pickerStyle(.segmented)
                    TextField(model.isSubscription ? "Name (e.g. Netflix)" : "Name (e.g. Rent)", text: $model.name)
                        .accessibilityIdentifier("recurring.name")
                    MoneyField("Amount", text: $model.amountText)
                        .accessibilityIdentifier("recurring.amount")
                }
                Section {
                    Picker("Repeats", selection: $model.frequency) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    DatePicker(model.isEditing ? "First due" : "Next due", selection: $model.startDate, displayedComponents: .date)
                    Picker("Category", selection: $model.categoryID) {
                        ForEach(CategoryCatalog.categories(for: model.kind)) { category in
                            Label(category.name, systemImage: category.symbol).tag(category.id)
                        }
                    }
                    Picker("Account", selection: $model.accountID) {
                        ForEach(model.accounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                Section {
                    if model.kind == .expense {
                        Toggle("Subscription", isOn: $model.isSubscription)
                    }
                    Toggle("Add automatically on due date", isOn: $model.autoPost)
                } footer: {
                    Text("Automatic items are posted once per due date, even if you use FlowMoney on several devices.")
                }
                if let error = model.errorMessage {
                    Section { ErrorBanner(error) }
                }
            }
            .navigationTitle(model.isEditing ? "Edit" : (model.isSubscription ? "New Subscription" : "New Recurring"))
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
                    .accessibilityIdentifier("recurring.save")
                }
            }
            .onChange(of: model.kind) { _, kind in
                if model.categoryID.category.kind != kind {
                    model.categoryID = kind == .income ? .salary : .bills
                }
            }
            .task { await model.load() }
        }
        .environment(\.currency, model.currency)
    }
}
