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
final class GoalsModel: LedgerObserving {
    private(set) var goals: [GoalStatus] = []
    private(set) var totalSaved = Money.zero
    private(set) var isLoaded = false

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
    }

    func update(with snapshot: LedgerSnapshot) {
        goals = GoalProgress.statuses(for: snapshot, now: context.now(), calendar: context.calendar)
        totalSaved = goals.sum(\.saved)
        isLoaded = true
    }
}

/// Screen 13 — savings goals.
public struct GoalsView: View {
    @State private var model: GoalsModel
    @Environment(Router.self) private var router

    public init(context: LedgerContext) {
        _model = State(initialValue: GoalsModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 6) {
                Text("Plan today for a brighter tomorrow").font(.title3.bold())
                HStack(spacing: 4) {
                    Text("Saved so far:")
                    AmountText(model.totalSaved).fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .bottomLeading)
            .background(alignment: .topTrailing) {
                Image(systemName: "airplane.departure")
                    .font(.system(size: 64))
                    .foregroundStyle(.white.opacity(0.2))
                    .padding(16)
            }
            .background(Theme.heroGradient, in: .rect(cornerRadius: 24))

            if model.isLoaded, model.goals.isEmpty {
                ContentUnavailableView {
                    Label("No goals yet", systemImage: "target")
                } description: {
                    Text("A trip, a car, an emergency fund — give your savings a purpose.")
                }
            }

            VStack(spacing: 0) {
                ForEach(model.goals) { status in
                    NavigationLink(value: Route.goal(status.id)) {
                        GoalRow(status: status)
                    }
                    .buttonStyle(.plain)
                    if status.id != model.goals.last?.id {
                        Divider().padding(.leading, 80)
                    }
                }
            }
            .card(padding: 0)
            .opacity(model.goals.isEmpty ? 0 : 1)

            Button {
                router.present(.goalEditor())
            } label: {
                Label("Create a Goal", systemImage: "plus")
            }
            .buttonStyle(.primary)
            .accessibilityIdentifier("goals.add")
        }
        .navigationTitle("Savings Goals")
        .task { await model.observe() }
    }
}

struct GoalRow: View {
    let status: GoalStatus

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                ProgressRing(fraction: status.fraction, color: status.goal.symbol.color, lineWidth: 6)
                Image(systemName: status.goal.symbol.symbol).foregroundStyle(status.goal.symbol.color)
            }
            .frame(width: 50, height: 50)
            VStack(alignment: .leading, spacing: 4) {
                Text(status.goal.name).font(.body.weight(.semibold))
                HStack(spacing: 2) {
                    AmountText(status.saved)
                    Text("of")
                    AmountText(status.goal.target)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                if !status.isComplete {
                    Text(status.isOnTrack ? "On track" : "Behind schedule")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(status.isOnTrack ? Theme.income : Theme.warning)
                }
            }
            Spacer()
            Text(status.fraction, format: .percent.precision(.fractionLength(0)))
                .font(.subheadline.weight(.bold))
                .foregroundStyle(status.goal.symbol.color)
        }
        .padding(16)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Detail (screen 14)

@MainActor
@Observable
final class GoalDetailModel: LedgerObserving {
    private(set) var status: GoalStatus?
    private(set) var monthly: [DatedAmount] = []
    private(set) var contributions: [GoalContribution] = []
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
        guard let goal = snapshot.goals.first(where: { $0.id == id }) else {
            isMissing = true
            status = nil
            return
        }
        status = GoalProgress.status(for: goal, in: snapshot, now: context.now(), calendar: context.calendar)
        monthly = GoalProgress.monthlyContributions(for: id, in: snapshot, months: 6, now: context.now(), calendar: context.calendar)
        contributions = snapshot.contributions.filter { $0.goalID == id }
    }

    func delete() async -> Bool {
        do {
            try await context.repository.perform(.deleteGoal(id: id))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func deleteContribution(_ contribution: GoalContribution) async {
        do {
            try await context.repository.perform(.deleteContribution(id: contribution.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

public struct GoalDetailView: View {
    @State private var model: GoalDetailModel
    @State private var confirmsDelete = false
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    public init(context: LedgerContext, id: UUID) {
        _model = State(initialValue: GoalDetailModel(context: context, id: id))
    }

    public var body: some View {
        Group {
            if let status = model.status {
                content(status)
            } else if model.isMissing {
                ContentUnavailableView("Goal deleted", systemImage: "trash")
            } else {
                LoadingView()
            }
        }
        .background(Theme.background)
        .navigationTitle(model.status?.goal.name ?? "Goal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit Goal", systemImage: "pencil") { router.present(.goalEditor(editing: model.id)) }
                    Button("Delete Goal", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Goal options")
            }
        }
        .confirmationDialog("Delete this goal and its history?", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task {
                if await model.delete() {
                    dismiss()
                }
            } }
        }
        .task { await model.observe() }
        .errorAlert($model.errorMessage)
    }

    private func content(_ status: GoalStatus) -> some View {
        List {
            Section {
                header(status)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                if let date = status.goal.targetDate {
                    LabeledContent("Target date", value: date.formatted(date: .abbreviated, time: .omitted))
                }
                LabeledContent("Remaining") { AmountText(status.remaining) }
                LabeledContent("Monthly plan") { AmountText(status.goal.monthlyContribution) }
                if let required = status.requiredMonthly, !status.isOnTrack {
                    LabeledContent("Needed per month") { AmountText(required).foregroundStyle(Theme.warning) }
                }
            }

            Section("Progress") {
                Chart(model.monthly) { point in
                    BarMark(x: .value("Month", point.date, unit: .month), y: .value("Saved", Double(point.amount.minorUnits) / 100))
                        .foregroundStyle(status.goal.symbol.color.gradient)
                        .cornerRadius(6)
                }
                .frame(height: 160)
                .padding(.vertical, 8)
            }

            Section("History") {
                if model.contributions.isEmpty {
                    Text("No money added yet.").foregroundStyle(.secondary)
                }
                ForEach(model.contributions) { contribution in
                    HStack {
                        Text(contribution.date.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        AmountText(contribution.amount, style: .signed)
                    }
                    .swipeActions {
                        Button("Delete", role: .destructive) { Task { await model.deleteContribution(contribution) } }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button {
                router.present(.contribution(goalID: model.id))
            } label: {
                Label("Add Money", systemImage: "plus")
            }
            .buttonStyle(.primary)
            .padding(16)
            .background(.bar)
            .accessibilityIdentifier("goal.addMoney")
        }
    }

    private func header(_ status: GoalStatus) -> some View {
        VStack(spacing: 12) {
            ZStack {
                ProgressRing(fraction: status.fraction, color: status.goal.symbol.color, lineWidth: 12)
                VStack(spacing: 2) {
                    Image(systemName: status.goal.symbol.symbol).font(.title2).foregroundStyle(status.goal.symbol.color)
                    Text(status.fraction, format: .percent.precision(.fractionLength(0))).font(.title2.bold())
                }
            }
            .frame(width: 140, height: 140)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                AmountText(status.saved).font(.title2.bold())
                Text("of").foregroundStyle(.secondary)
                AmountText(status.goal.target).foregroundStyle(.secondary)
            }
            if status.isComplete {
                Label("Goal reached!", systemImage: "party.popper.fill").foregroundStyle(Theme.income).font(.headline)
            } else {
                Text(status.isOnTrack ? "You're on track 🎯" : "A little behind — top it up to catch up")
                    .font(.subheadline)
                    .foregroundStyle(status.isOnTrack ? Theme.income : Theme.warning)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
