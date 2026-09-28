public import Foundation
public import LedgerUI
public import SwiftUI
import Charts
import DesignSystem
import Domain
import FlowCore
import Observation
import Routing

@MainActor
@Observable
final class BudgetsModel: LedgerObserving {
    var month: YearMonth
    private(set) var summary: BudgetSummary?
    private var snapshot: LedgerSnapshot?

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
        month = context.currentMonth
    }

    func update(with snapshot: LedgerSnapshot) {
        self.snapshot = snapshot
        recompute()
    }

    func move(by months: Int) {
        let target = month.adding(months: months)
        guard target <= context.currentMonth else { return }
        month = target
        recompute()
    }

    var canGoForward: Bool {
        month < context.currentMonth
    }

    private func recompute() {
        guard let snapshot else { return }
        summary = BudgetProgress.summary(for: snapshot, month: month, now: context.now(), calendar: context.calendar)
    }
}

/// Screen 11 — monthly budgets with progress per category.
public struct BudgetsView: View {
    @State private var model: BudgetsModel
    @Environment(Router.self) private var router

    public init(context: LedgerContext) {
        _model = State(initialValue: BudgetsModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            HStack {
                Button { model.move(by: -1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(model.month.title(in: model.context.calendar)).font(.headline)
                Spacer()
                Button { model.move(by: 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward)
                    .accessibilityLabel("Next month")
            }
            .tint(Theme.brand)

            if let summary = model.summary {
                if summary.statuses.isEmpty {
                    ContentUnavailableView {
                        Label("No budgets yet", systemImage: "chart.pie")
                    } description: {
                        Text("Set a monthly limit for a category and FlowMoney will warn you before you go over.")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            AmountText(summary.totalSpent).font(.title.bold())
                            Text("of").foregroundStyle(.secondary)
                            AmountText(summary.totalLimit).foregroundStyle(.secondary)
                        }
                        ProgressBar(fraction: summary.fraction, color: summary.fraction > 1 ? Theme.expense : Theme.brand, height: 12)
                        Text("\(summary.fraction, format: .percent.precision(.fractionLength(0))) of your total budget used")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .card()

                    VStack(spacing: 0) {
                        ForEach(summary.statuses) { status in
                            NavigationLink(value: Route.budget(status.id)) {
                                BudgetRow(status: status)
                            }
                            .buttonStyle(.plain)
                            if status.id != summary.statuses.last?.id {
                                Divider().padding(.leading, 68)
                            }
                        }
                    }
                    .card(padding: 0)
                }
            }

            Button {
                router.present(.budgetEditor())
            } label: {
                Label("Add Budget", systemImage: "plus")
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("budgets.add")
        }
        .navigationTitle("Budgets")
        .task { await model.observe() }
    }
}

struct BudgetRow: View {
    let status: BudgetStatus

    var body: some View {
        let category = status.budget.categoryID.category
        HStack(spacing: 12) {
            IconBadge(category.symbol, color: category.color, size: 40)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(category.name).font(.subheadline.weight(.medium))
                    Spacer()
                    HStack(spacing: 2) {
                        AmountText(status.spent, style: .whole)
                        Text("/")
                        AmountText(status.budget.limit, style: .whole)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
                ProgressBar(fraction: status.fraction, color: status.level.color)
                HStack {
                    Text(status.fraction, format: .percent.precision(.fractionLength(0)))
                    Spacer()
                    if status.level == .over {
                        HStack(spacing: 2) {
                            Text("Over by")
                            AmountText(status.remaining.magnitude, style: .whole)
                        }
                    } else if status.isProjectedOver {
                        Text("On pace to go over")
                    }
                }
                .font(.caption)
                .foregroundStyle(status.level == .onTrack && !status.isProjectedOver ? Color.secondary : status.level == .over ? Theme
                    .expense : Theme.warning)
            }
        }
        .padding(16)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail (screen 12)

@MainActor
@Observable
final class BudgetDetailModel: LedgerObserving {
    private(set) var status: BudgetStatus?
    private(set) var history: [MonthFlow] = []
    private(set) var daily: [DatedAmount] = []
    private(set) var merchants: [(name: String, amount: Money, share: Double)] = []
    private(set) var isMissing = false
    var errorMessage: String?

    let context: LedgerContext
    var lastRevision: Int?
    let id: UUID

    init(context: LedgerContext, id: UUID) {
        self.context = context
        self.id = id
    }

    func update(with snapshot: LedgerSnapshot) {
        let month = context.currentMonth
        let calendar = context.calendar
        guard let budget = snapshot.budgets.first(where: { $0.id == id }) else {
            isMissing = true
            status = nil
            return
        }
        let summary = BudgetProgress.summary(for: snapshot, month: month, now: context.now(), calendar: calendar)
        status = summary.statuses.first { $0.id == id }
        daily = BudgetProgress.dailySpending(category: budget.categoryID, in: snapshot, month: month, calendar: calendar)
        history = month.trailing(6).map { month in
            let spent = snapshot.transactions(in: month, calendar: calendar)
                .filter { $0.kind == .expense && $0.categoryID == budget.categoryID }
                .sum(\.amount)
            return MonthFlow(month: month, income: .zero, expenses: spent)
        }
        var byMerchant: [String: Money] = [:]
        for transaction in snapshot.transactions(in: month, calendar: calendar)
            where transaction.kind == .expense && transaction.categoryID == budget.categoryID {
            byMerchant[transaction.displayTitle, default: .zero] += transaction.amount
        }
        let total = byMerchant.values.sum()
        merchants = byMerchant.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value, $0.value.fraction(of: total)) }
    }

    func delete() async -> Bool {
        do {
            try await context.repository.perform(.deleteBudget(id: id))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

public struct BudgetDetailView: View {
    @State private var model: BudgetDetailModel
    @State private var confirmsDelete = false
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    public init(context: LedgerContext, id: UUID) {
        _model = State(initialValue: BudgetDetailModel(context: context, id: id))
    }

    public var body: some View {
        Group {
            if let status = model.status {
                content(status)
            } else if model.isMissing {
                ContentUnavailableView("Budget deleted", systemImage: "trash")
            } else {
                LoadingView()
            }
        }
        .background(Theme.background)
        .navigationTitle(model.status?.budget.categoryID.category.name ?? "Budget")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Limit", systemImage: "pencil") { router.present(.budgetEditor(editing: model.id)) }
                    Button("Delete Budget", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Budget options")
            }
        }
        .confirmationDialog("Delete this budget?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task {
                    if await model.delete() {
                        dismiss()
                    }
                }
            }
        }
        .task { await model.observe() }
        .errorAlert($model.errorMessage)
    }

    private func content(_ status: BudgetStatus) -> some View {
        let category = status.budget.categoryID.category
        return ScreenScroll {
            VStack(spacing: 12) {
                IconBadge(category.symbol, color: category.color, size: 56)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    AmountText(status.spent).font(.title.bold())
                    Text("of").foregroundStyle(.secondary)
                    AmountText(status.budget.limit).foregroundStyle(.secondary)
                }
                ProgressBar(fraction: status.fraction, color: status.level.color, height: 12)
                HStack {
                    Text(status.fraction, format: .percent.precision(.fractionLength(0)))
                    Spacer()
                    if status.remaining.isNegative {
                        HStack(spacing: 2) {
                            AmountText(status.remaining.magnitude)
                            Text("over")
                        }
                        .foregroundStyle(Theme.expense)
                    } else {
                        HStack(spacing: 2) {
                            AmountText(status.remaining)
                            Text("left")
                        }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if status.isProjectedOver, status.level != .over {
                    Label {
                        HStack(spacing: 3) {
                            Text("Projected")
                            AmountText(status.projected)
                            Text("by month end")
                        }
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.warning)
                }
            }
            .frame(maxWidth: .infinity)
            .card()

            VStack(alignment: .leading, spacing: 12) {
                SectionHeader("Last 6 months")
                Chart(model.history) { flow in
                    BarMark(
                        x: .value("Month", flow.month.shortTitle(in: model.context.calendar)),
                        y: .value("Spent", Double(flow.expenses.minorUnits) / 100)
                    )
                    .foregroundStyle(flow.month == model.context.currentMonth ? Theme.brand : Theme.brand.opacity(0.35))
                    .cornerRadius(6)
                    RuleMark(y: .value("Limit", Double(status.budget.limit.minorUnits) / 100))
                        .foregroundStyle(Theme.expense.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .frame(height: 180)
                .accessibilityLabel("Monthly spending for \(category.name) over the last six months")
            }
            .card()

            if !model.merchants.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader("Spending breakdown")
                    ForEach(model.merchants, id: \.name) { merchant in
                        HStack(spacing: 12) {
                            MonogramBadge(merchant.name, size: 34)
                            Text(merchant.name).font(.subheadline)
                            Spacer()
                            AmountText(merchant.amount).font(.subheadline.weight(.semibold))
                            Text(merchant.share, format: .percent.precision(.fractionLength(0)))
                                .font(.caption).foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .card()
            }
        }
    }
}
