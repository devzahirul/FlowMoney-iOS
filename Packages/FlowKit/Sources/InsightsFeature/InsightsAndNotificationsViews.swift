public import LedgerUI
public import SwiftUI
import DesignSystem
import Domain
import FlowCore
import Observation
import Routing

@MainActor
@Observable
final class InsightsModel: LedgerObserving {
    private(set) var insights: [Insight] = []
    private(set) var isLoaded = false

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
    }

    func update(with snapshot: LedgerSnapshot) {
        insights = InsightEngine.insights(for: snapshot, now: context.now(), calendar: context.calendar)
        isLoaded = true
    }
}

/// Screen 20 — personalised tips generated from the ledger.
public struct InsightsView: View {
    @State private var model: InsightsModel

    public init(context: LedgerContext) {
        _model = State(initialValue: InsightsModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            ForEach(model.insights) { insight in
                InsightCard(insight: insight)
            }
            if model.isLoaded, model.insights.isEmpty {
                ContentUnavailableView(
                    "No insights yet",
                    systemImage: "lightbulb",
                    description: Text("Add a few weeks of transactions and FlowMoney will start spotting patterns.")
                )
            }
        }
        .navigationTitle("Insights")
        .task { await model.observe() }
    }
}

// MARK: - Notifications (screen 24)

@MainActor
@Observable
final class NotificationsModel: LedgerObserving {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All", alerts = "Alerts", updates = "Updates"
        var id: Self {
            self
        }
    }

    var filter = Filter.all
    private(set) var alerts: [LedgerAlert] = []
    private(set) var isLoaded = false

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
    }

    func update(with snapshot: LedgerSnapshot) {
        alerts = AlertFeed.alerts(for: snapshot, now: context.now(), calendar: context.calendar)
        isLoaded = true
    }

    var visible: [LedgerAlert] {
        switch filter {
        case .all: alerts
        case .alerts: alerts.filter(\.isAlert)
        case .updates: alerts.filter { !$0.isAlert }
        }
    }

    static func route(for alert: LedgerAlert) -> Route? {
        switch alert.kind {
        case .budget: alert.subjectID.map(Route.budget) ?? .budgets
        case .goal: alert.subjectID.map(Route.goal) ?? .goals
        case .largeTransaction: alert.subjectID.map(Route.transaction)
        case .renewal: .subscriptions
        case .weeklyReport: .spendingAnalytics
        }
    }
}

public struct NotificationsView: View {
    @State private var model: NotificationsModel
    @Environment(AppPreferences.self) private var preferences

    public init(context: LedgerContext) {
        _model = State(initialValue: NotificationsModel(context: context))
    }

    public var body: some View {
        List {
            Section {
                Picker("Filter", selection: $model.filter) {
                    ForEach(NotificationsModel.Filter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(model.visible) { alert in
                    let isUnread = !preferences.readAlertIDs.contains(alert.id)
                    NavigationLink(value: NotificationsModel.route(for: alert) ?? .notifications) {
                        AlertRow(alert: alert, isUnread: isUnread, now: model.context.now())
                    }
                    .simultaneousGesture(TapGesture().onEnded { preferences.markRead([alert.id]) })
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if model.isLoaded, model.visible.isEmpty {
                ContentUnavailableView(
                    "You're all caught up",
                    systemImage: "bell.badge",
                    description: Text("Budget alerts, goal milestones and renewals show up here.")
                )
            }
        }
        .navigationTitle("Notifications")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Mark all read") { preferences.markRead(model.alerts.map(\.id)) }
                    .disabled(model.alerts.allSatisfy { preferences.readAlertIDs.contains($0.id) })
            }
        }
        .task { await model.observe() }
    }
}

struct AlertRow: View {
    let alert: LedgerAlert
    let isUnread: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(symbol, color: color, size: 40)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(alert.title).font(.subheadline.weight(isUnread ? .semibold : .regular))
                    Spacer()
                    Text(alert.date, format: .relative(presentation: .named, unitsStyle: .abbreviated))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Text(alert.message).font(.footnote).foregroundStyle(.secondary)
            }
            if isUnread {
                Circle().fill(Theme.brand).frame(width: 8, height: 8).padding(.top, 6)
                    .accessibilityLabel("Unread")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch alert.kind {
        case .budget: "exclamationmark.triangle.fill"
        case .goal: "target"
        case .largeTransaction: "creditcard.fill"
        case .renewal: "arrow.triangle.2.circlepath"
        case .weeklyReport: "doc.text.fill"
        }
    }

    private var color: Color {
        switch alert.kind {
        case .budget: Theme.warning
        case .goal: Theme.income
        case .largeTransaction: Theme.expense
        case .renewal: Theme.palette[1]
        case .weeklyReport: Theme.brand
        }
    }
}
