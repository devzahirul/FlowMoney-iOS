public import LedgerUI
public import SwiftUI
import Charts
import DesignSystem
import Domain
import FlowCore
import Routing

/// Screen 4 — the dashboard.
public struct HomeView: View {
    @State private var model: HomeViewModel
    @Environment(Router.self) private var router
    @Environment(AppPreferences.self) private var preferences

    public init(context: LedgerContext) {
        _model = State(initialValue: HomeViewModel(context: context))
    }

    public var body: some View {
        Group {
            if let state = model.state {
                content(state)
            } else {
                LoadingView()
            }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.observe() }
        .task { await model.observeSyncStatus() }
    }

    private func content(_ state: HomeState) -> some View {
        ScreenScroll {
            header(state)
            if !state.hasAccounts {
                emptyState
            } else {
                BalanceCard(state: state, syncStatus: model.syncStatus)
                QuickActions()
                overview(state)
                if !state.budgets.isEmpty {
                    budgets(state)
                }
                recent(state)
            }
        }
        .refreshable { await model.refresh() }
    }

    private func header(_ state: HomeState) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                TimelineView(.everyMinute) { context in
                    Text(model.greeting(at: context.date)).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(state.firstName.isEmpty ? "Welcome 👋" : "\(state.firstName) 👋")
                    .font(.title2.bold())
            }
            Spacer()
            let unread = state.alertIDs.filter { !preferences.readAlertIDs.contains($0) }.count
            NavigationLink(value: Route.notifications) {
                Image(systemName: "bell")
                    .font(.title3)
                    .frame(width: 44, height: 44)
                    .background(Theme.card, in: .circle)
                    .overlay(alignment: .topTrailing) {
                        if unread > 0 {
                            Circle().fill(Theme.expense).frame(width: 10, height: 10).offset(x: -8, y: 8)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(unread > 0 ? "Notifications, \(unread) unread" : "Notifications")
            .accessibilityIdentifier("home.notifications")
            Button {
                router.select(.profile)
            } label: {
                Text(state.initials)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.onBrand)
                    .frame(width: 44, height: 44)
                    .background(Theme.brand.gradient, in: .circle)
            }
            .accessibilityLabel("Profile")
        }
        .padding(.top, 8)
    }

    private func overview(_ state: HomeState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("This month") {
                NavigationLink("Cash flow", value: Route.cashFlow)
            }
            HStack(spacing: 12) {
                FlowTile(title: "Income", amount: state.income, symbol: "arrow.down.left", color: Theme.income)
                FlowTile(title: "Expenses", amount: state.expenses, symbol: "arrow.up.right", color: Theme.expense)
            }
        }
    }

    private func budgets(_ state: HomeState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Budgets") {
                NavigationLink("See all", value: Route.budgets)
            }
            VStack(spacing: 14) {
                ForEach(state.budgets) { status in
                    NavigationLink(value: Route.budget(status.id)) {
                        BudgetLine(status: status)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    private func recent(_ state: HomeState) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Recent transactions") {
                NavigationLink("See all", value: Route.transactions())
                    .accessibilityIdentifier("home.seeAllTransactions")
            }
            if state.recent.isEmpty {
                Text("No transactions yet. Tap Expense to add your first one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .card()
            } else {
                VStack(spacing: 4) {
                    ForEach(state.recent) { transaction in
                        NavigationLink(value: Route.transaction(transaction.id)) {
                            TransactionRow(
                                transaction,
                                subtitle: transaction.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .card(padding: 12)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            IconBadge("building.columns.fill", color: Theme.brand, size: 64)
            Text("Add your first account").font(.title3.bold())
            Text("Accounts hold your balances — checking, savings, cards or cash.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Add Account") { router.present(.accountEditor()) }
                .buttonStyle(.primary)
                .accessibilityIdentifier("home.addAccount")
        }
        .padding(24)
        .card()
        .padding(.top, 40)
    }
}

// MARK: - Pieces

struct BalanceCard: View {
    let state: HomeState
    let syncStatus: SyncStatus
    @Environment(\.hideAmounts) private var hideAmounts

    var body: some View {
        NavigationLink(value: Route.netWorth) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Total balance").font(.subheadline.weight(.medium)).opacity(0.85)
                    Spacer()
                    SyncBadge(status: syncStatus)
                }
                AmountText(state.totalBalance)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                HStack {
                    if let change = state.monthChange {
                        Label {
                            Text("\(change >= 0 ? "+" : "")\(change.formatted(.percent.precision(.fractionLength(1)))) this month")
                        } icon: {
                            Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        }
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.18), in: .capsule)
                    }
                    Spacer()
                }
                if state.balanceHistory.count > 1, !hideAmounts {
                    Chart(state.balanceHistory) { point in
                        LineMark(x: .value("Month", point.date), y: .value("Balance", point.amount.minorUnits))
                            .interpolationMethod(.catmullRom)
                            .foregroundStyle(.white)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 44)
                    .accessibilityHidden(true)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.heroGradient, in: .rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows net worth")
    }
}

struct SyncBadge: View {
    let status: SyncStatus

    var body: some View {
        switch status.phase {
        case .localOnly:
            Label("Demo", systemImage: "iphone").badgeStyle()
        case .offline:
            Label("Offline", systemImage: "wifi.slash").badgeStyle()
        case .syncing:
            ProgressView().tint(.white).controlSize(.small)
        case .failed:
            Label("Sync issue", systemImage: "exclamationmark.icloud").badgeStyle()
        case .idle:
            if status.pendingChanges > 0 {
                Label("\(status.pendingChanges) pending", systemImage: "icloud.and.arrow.up").badgeStyle()
            }
        }
    }
}

private extension Label where Title == Text, Icon == Image {
    func badgeStyle() -> some View {
        font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.white.opacity(0.18), in: .capsule)
    }
}

struct QuickActions: View {
    @Environment(Router.self) private var router

    var body: some View {
        HStack(spacing: 0) {
            action("Expense", "minus", id: "expense") { router.present(.transactionEditor(kind: .expense)) }
            action("Income", "plus", id: "income") { router.present(.transactionEditor(kind: .income)) }
            action("Accounts", "building.columns", id: "accounts") { router.push(.accounts) }
            action("Report", "doc.text", id: "report") { router.push(.monthlyReport) }
        }
        .card(padding: 12)
    }

    private func action(_ title: String, _ symbol: String, id: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.brand)
                    .frame(width: 48, height: 48)
                    .background(Theme.brandSoft, in: .circle)
                Text(title).font(.caption.weight(.medium)).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.action.\(id)")
    }
}

struct FlowTile: View {
    let title: String
    let amount: Money
    let symbol: String
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            IconBadge(symbol, color: color, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                AmountText(amount).font(.headline).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct BudgetLine: View {
    let status: BudgetStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(status.budget.categoryID.category.name, systemImage: status.budget.categoryID.category.symbol)
                    .font(.subheadline.weight(.medium))
                Spacer()
                HStack(spacing: 2) {
                    AmountText(status.spent, style: .whole)
                    Text("/").foregroundStyle(.secondary)
                    AmountText(status.budget.limit, style: .whole).foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
            ProgressBar(fraction: status.fraction, color: status.level.color)
        }
        .accessibilityElement(children: .combine)
    }
}
