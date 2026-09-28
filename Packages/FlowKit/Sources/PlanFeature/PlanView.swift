public import LedgerUI
public import SwiftUI
import DesignSystem
import Domain
import FlowCore
import Observation
import Routing

@MainActor
@Observable
final class PlanModel: LedgerObserving {
    private(set) var budget: BudgetSummary?
    private(set) var goals: [GoalStatus] = []
    private(set) var subscriptionsMonthly = Money.zero
    private(set) var subscriptionCount = 0
    private(set) var upcoming: [(rule: RecurringRule, date: Date)] = []

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
    }

    func update(with snapshot: LedgerSnapshot) {
        let now = context.now()
        budget = BudgetProgress.summary(for: snapshot, month: context.currentMonth, now: now, calendar: context.calendar)
        goals = GoalProgress.statuses(for: snapshot, now: now, calendar: context.calendar)
        let subscriptions = snapshot.recurringRules.filter { $0.isSubscription && !$0.isPaused }
        subscriptionCount = subscriptions.count
        subscriptionsMonthly = subscriptions.sum(\.monthlyEquivalent)
        upcoming = snapshot.recurringRules
            .filter { !$0.isPaused }
            .compactMap { rule in rule.nextOccurrence(onOrAfter: now, calendar: context.calendar).map { (rule, $0) } }
            .sorted { $0.date < $1.date }
            .prefix(4)
            .map(\.self)
    }
}

/// "Plan" tab root: budgets, goals and bills at a glance.
public struct PlanView: View {
    @State private var model: PlanModel
    @Environment(Router.self) private var router

    public init(context: LedgerContext) {
        _model = State(initialValue: PlanModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            budgetCard
            goalsSection
            billsSection
        }
        .navigationTitle("Plan")
        .task { await model.observe() }
    }

    @ViewBuilder
    private var budgetCard: some View {
        if let budget = model.budget {
            NavigationLink(value: Route.budgets) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Budgets", systemImage: "chart.pie.fill").font(.headline)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                    }
                    if budget.statuses.isEmpty {
                        Text("Set monthly limits for the categories you want to keep in check.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            AmountText(budget.totalSpent, style: .whole).font(.title2.bold())
                            Text("of").foregroundStyle(.secondary)
                            AmountText(budget.totalLimit, style: .whole).foregroundStyle(.secondary)
                        }
                        ProgressBar(fraction: budget.fraction, color: budget.fraction > 1 ? Theme.expense : Theme.brand, height: 10)
                        Text("\(budget.statuses.filter { $0.level != .onTrack }.count) of \(budget.statuses.count) budgets need attention")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .card()
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("plan.budgets")
        }
    }

    private var goalsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Savings goals") {
                NavigationLink("See all", value: Route.goals)
            }
            if model.goals.isEmpty {
                Button {
                    router.present(.goalEditor())
                } label: {
                    Label("Create your first goal", systemImage: "target")
                }
                .buttonStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(model.goals) { status in
                            NavigationLink(value: Route.goal(status.id)) {
                                GoalCard(status: status)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollClipDisabled()
            }
        }
    }

    private var billsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Bills & subscriptions")
            HStack(spacing: 12) {
                NavigationLink(value: Route.subscriptions) {
                    VStack(alignment: .leading, spacing: 6) {
                        IconBadge("play.rectangle.fill", color: Theme.palette[1], size: 36)
                        Text("Subscriptions").font(.subheadline.weight(.medium))
                        HStack(spacing: 2) {
                            AmountText(model.subscriptionsMonthly)
                            Text("/mo")
                        }
                        .font(.footnote).foregroundStyle(.secondary)
                    }
                    .card(padding: 14)
                }
                .accessibilityIdentifier("plan.subscriptions")
                NavigationLink(value: Route.recurring) {
                    VStack(alignment: .leading, spacing: 6) {
                        IconBadge("repeat", color: Theme.palette[2], size: 36)
                        Text("Recurring").font(.subheadline.weight(.medium))
                        Text("Bills & paychecks").font(.footnote).foregroundStyle(.secondary)
                    }
                    .card(padding: 14)
                }
            }
            .buttonStyle(.plain)
            if !model.upcoming.isEmpty {
                VStack(spacing: 0) {
                    ForEach(model.upcoming, id: \.rule.id) { item in
                        UpcomingRow(rule: item.rule, date: item.date, now: model.context.now(), calendar: model.context.calendar)
                        if item.rule.id != model.upcoming.last?.rule.id {
                            Divider().padding(.leading, 64)
                        }
                    }
                }
                .card(padding: 0)
            }
        }
    }
}

struct GoalCard: View {
    let status: GoalStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                ProgressRing(fraction: status.fraction, color: status.goal.symbol.color, lineWidth: 6)
                Image(systemName: status.goal.symbol.symbol).foregroundStyle(status.goal.symbol.color)
            }
            .frame(width: 48, height: 48)
            Text(status.goal.name).font(.subheadline.weight(.semibold)).lineLimit(1)
            HStack(spacing: 2) {
                AmountText(status.saved, style: .whole)
                Text("/")
                AmountText(status.goal.target, style: .whole)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(width: 150, alignment: .leading)
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct UpcomingRow: View {
    let rule: RecurringRule
    let date: Date
    let now: Date
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 12) {
            MonogramBadge(rule.name, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(.subheadline.weight(.medium))
                Text(RelativeDay.phrase(for: date, now: now, calendar: calendar).sentenceCased)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(rule.kind == .income ? rule.amount : -rule.amount, style: .signed).font(.subheadline.weight(.semibold))
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }
}
