public import Domain
public import FlowCore
public import Foundation
public import LedgerUI
public import Observation
public import SwiftUI
import DesignSystem

@MainActor
@Observable
public final class GoalEditorModel {
    public var name = ""
    public var symbol = GoalSymbol.vacation
    public var targetText = ""
    public var monthlyText = ""
    public var hasDate = true
    public var targetDate: Date
    public private(set) var currency = CurrencyFormat.usd
    public var errorMessage: String?

    private let context: LedgerContext
    private let editingID: UUID?
    private var existing: Goal?

    public init(context: LedgerContext, editing: UUID?) {
        self.context = context
        editingID = editing
        targetDate = context.calendar.date(byAdding: .year, value: 1, to: context.now()) ?? context.now()
    }

    public var isEditing: Bool {
        editingID != nil
    }

    public var target: Money? {
        currency.parse(userInput: targetText).flatMap { $0.minorUnits > 0 ? $0 : nil }
    }

    public var monthly: Money? {
        monthlyText.isEmpty ? .zero : currency.parse(userInput: monthlyText)
    }

    public var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && target != nil && monthly != nil
    }

    /// Monthly amount that reaches the target on the chosen date — offered as a one-tap suggestion.
    public var suggestedMonthly: Money? {
        guard let target, hasDate else { return nil }
        let months = max(
            1,
            YearMonth(context.now(), calendar: context.calendar).months(to: YearMonth(targetDate, calendar: context.calendar))
        )
        return Money(minorUnits: (target.minorUnits + Int64(months) - 1) / Int64(months))
    }

    public func load() async {
        let snapshot = await context.repository.currentSnapshot()
        currency = snapshot.currency
        guard let editingID, let goal = snapshot.goals.first(where: { $0.id == editingID }) else { return }
        existing = goal
        name = goal.name
        symbol = goal.symbol
        targetText = currency.editingText(goal.target)
        monthlyText = currency.editingText(goal.monthlyContribution)
        hasDate = goal.targetDate != nil
        if let date = goal.targetDate {
            targetDate = date
        }
    }

    public func save() async -> Bool {
        guard let target, let monthly else { return false }
        let goal = Goal(
            id: existing?.id ?? UUID(),
            name: name,
            symbol: symbol,
            target: target,
            targetDate: hasDate ? targetDate : nil,
            monthlyContribution: monthly,
            createdAt: existing?.createdAt ?? context.now()
        )
        do {
            try await context.repository.perform(.saveGoal(goal))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

public struct GoalEditorView: View {
    @State private var model: GoalEditorModel
    @Environment(\.dismiss) private var dismiss

    public init(context: LedgerContext, editing: UUID?) {
        _model = State(initialValue: GoalEditorModel(context: context, editing: editing))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Goal name (e.g. Vacation in Japan)", text: $model.name)
                        .accessibilityIdentifier("goal.name")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(GoalSymbol.allCases, id: \.self) { symbol in
                                Button {
                                    model.symbol = symbol
                                } label: {
                                    IconBadge(symbol.symbol, color: symbol.color, size: 44)
                                        .overlay {
                                            if model.symbol == symbol {
                                                RoundedRectangle(cornerRadius: 13).stroke(Theme.brand, lineWidth: 2.5)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(symbol.title)
                                .accessibilityAddTraits(model.symbol == symbol ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                Section {
                    MoneyField("Target amount", text: $model.targetText)
                        .accessibilityIdentifier("goal.target")
                    Toggle("Target date", isOn: $model.hasDate.animation())
                    if model.hasDate {
                        DatePicker(
                            "Reach it by",
                            selection: $model.targetDate,
                            in: min(model.targetDate, Date())...,
                            displayedComponents: .date
                        )
                    }
                }
                Section {
                    MoneyField("Monthly saving", text: $model.monthlyText)
                } footer: {
                    if let suggested = model.suggestedMonthly {
                        Button("Save \(model.currency.string(suggested)) a month to get there on time") {
                            model.monthlyText = model.currency.editingText(suggested)
                        }
                        .font(.footnote)
                    }
                }
                if let error = model.errorMessage {
                    Section { ErrorBanner(error) }
                }
            }
            .navigationTitle(model.isEditing ? "Edit Goal" : "New Goal")
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
                    .accessibilityIdentifier("goal.save")
                }
            }
            .task { await model.load() }
        }
        .environment(\.currency, model.currency)
    }
}

// MARK: - Add money

@MainActor
@Observable
public final class ContributionModel {
    public var amountText = ""
    public var isWithdrawal = false
    public var date: Date
    public private(set) var goalName = ""
    public private(set) var remaining = Money.zero
    public private(set) var currency = CurrencyFormat.usd
    public var errorMessage: String?

    private let context: LedgerContext
    private let goalID: UUID

    public init(context: LedgerContext, goalID: UUID) {
        self.context = context
        self.goalID = goalID
        date = context.now()
    }

    public var amount: Money? {
        currency.parse(userInput: amountText).flatMap { $0.minorUnits > 0 ? $0 : nil }
    }

    public func load() async {
        let snapshot = await context.repository.currentSnapshot()
        currency = snapshot.currency
        guard let goal = snapshot.goals.first(where: { $0.id == goalID }) else { return }
        goalName = goal.name
        remaining = max(goal.target - snapshot.saved(toward: goalID), .zero)
    }

    public func save() async -> Bool {
        guard let amount else { return false }
        let contribution = GoalContribution(goalID: goalID, amount: isWithdrawal ? -amount : amount, date: date, createdAt: context.now())
        do {
            try await context.repository.perform(.saveContribution(contribution))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

public struct ContributionView: View {
    @State private var model: ContributionModel
    @Environment(\.dismiss) private var dismiss

    public init(context: LedgerContext, goalID: UUID) {
        _model = State(initialValue: ContributionModel(context: context, goalID: goalID))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $model.isWithdrawal) {
                    Text("Add money").tag(false)
                    Text("Withdraw").tag(true)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                Section {
                    MoneyField("Amount", text: $model.amountText)
                        .accessibilityIdentifier("contribution.amount")
                    DatePicker("Date", selection: $model.date, displayedComponents: .date)
                } footer: {
                    if !model.isWithdrawal, !model.remaining.isZero {
                        Text("\(model.currency.string(model.remaining)) to go on \(model.goalName).")
                    }
                }
                if let error = model.errorMessage {
                    Section { ErrorBanner(error) }
                }
            }
            .navigationTitle(model.goalName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(model.isWithdrawal ? "Withdraw" : "Add") { Task {
                        if await model.save() {
                            dismiss()
                        }
                    } }
                    .disabled(model.amount == nil)
                    .accessibilityIdentifier("contribution.save")
                }
            }
            .task { await model.load() }
        }
        .environment(\.currency, model.currency)
        .presentationDetents([.medium])
    }
}
