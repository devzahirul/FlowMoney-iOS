public import Domain
public import FlowCore
public import Foundation
public import LedgerUI
public import Observation

/// Everything the dashboard shows, derived from one snapshot in one pass.
public struct HomeState: Equatable, Sendable {
    public var firstName: String
    public var initials: String
    public var totalBalance: Money
    /// Change in net worth since the end of last month, as a fraction of last month's value.
    public var monthChange: Double?
    public var balanceHistory: [DatedAmount]
    public var income: Money
    public var expenses: Money
    public var budgets: [BudgetStatus]
    public var recent: [LedgerTransaction]
    public var alertIDs: [String]
    public var hasAccounts: Bool
}

@MainActor
@Observable
public final class HomeViewModel: LedgerObserving {
    public private(set) var state: HomeState?
    public private(set) var syncStatus: SyncStatus = .localOnly
    public let context: LedgerContext
    public var lastRevision: Int?

    public init(context: LedgerContext) {
        self.context = context
    }

    public func update(with snapshot: LedgerSnapshot) {
        state = Self.makeState(snapshot, now: context.now(), calendar: context.calendar)
    }

    public func observeSyncStatus() async {
        for await status in await context.repository.syncStatus() {
            syncStatus = status
        }
    }

    public func refresh() async {
        await context.repository.synchronize()
    }

    /// "Good morning" / "Good afternoon" / "Good evening".
    public func greeting(at date: Date) -> String {
        switch context.calendar.component(.hour, from: date) {
        case 5 ..< 12: "Good morning"
        case 12 ..< 18: "Good afternoon"
        default: "Good evening"
        }
    }

    static func makeState(_ snapshot: LedgerSnapshot, now: Date, calendar: Calendar) -> HomeState {
        let month = YearMonth(now, calendar: calendar)
        let netWorth = NetWorth.summary(for: snapshot, months: 6, now: now, calendar: calendar)
        let previous = netWorth.history.dropLast().last?.amount ?? .zero
        let flow = CashFlow.month(month, in: snapshot, calendar: calendar)
        let budgets = BudgetProgress.summary(for: snapshot, month: month, now: now, calendar: calendar).statuses
            .sorted { $0.fraction > $1.fraction }
        return HomeState(
            firstName: snapshot.profile.firstName,
            initials: snapshot.profile.initials,
            totalBalance: netWorth.total,
            monthChange: previous.isZero ? nil : netWorth.monthChange.fraction(of: previous.magnitude),
            balanceHistory: netWorth.history,
            income: flow.income,
            expenses: flow.expenses,
            budgets: Array(budgets.prefix(3)),
            recent: Array(snapshot.transactions.lazy.filter { $0.date <= now }.prefix(5)),
            alertIDs: AlertFeed.alerts(for: snapshot, now: now, calendar: calendar).map(\.id),
            hasAccounts: !snapshot.accounts.isEmpty
        )
    }
}
