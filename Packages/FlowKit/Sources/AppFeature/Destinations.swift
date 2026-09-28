import AccountsFeature
import ActivityFeature
import Domain
import InsightsFeature
import LedgerUI
import PlanFeature
import ProfileFeature
import Routing
import SwiftUI

/// The single place that knows which feature implements each route — the only file that imports every feature.
struct RouteDestination: View {
    let route: Route
    let scope: AppModel.SessionScope

    var body: some View {
        let context = scope.context
        switch route {
        case .accounts: AccountsView(context: context)
        case let .account(id): AccountDetailView(context: context, id: id)
        case let .transactions(filter): TransactionsView(context: context, filter: filter)
        case let .transaction(id): TransactionDetailView(context: context, id: id)
        case .search: SearchView(context: context)
        case .calendar: CalendarView(context: context)
        case .budgets: BudgetsView(context: context)
        case let .budget(id): BudgetDetailView(context: context, id: id)
        case .goals: GoalsView(context: context)
        case let .goal(id): GoalDetailView(context: context, id: id)
        case .subscriptions: RecurringListView(context: context, subscriptionsOnly: true)
        case .recurring: RecurringListView(context: context, subscriptionsOnly: false)
        case .cashFlow: CashFlowView(context: context)
        case .spendingAnalytics: SpendingAnalyticsView(context: context)
        case .monthlyReport: MonthlyReportView(context: context)
        case .netWorth: NetWorthView(context: context)
        case .insights: InsightsView(context: context)
        case .notifications: NotificationsView(context: context)
        case .settings: SettingsView(context: context, services: scope.services)
        case .security: SecurityView(services: scope.services)
        case .export: ExportView(context: context)
        }
    }
}

struct SheetDestination: View {
    let sheet: SheetRoute
    let scope: AppModel.SessionScope

    var body: some View {
        let context = scope.context
        switch sheet {
        case let .transactionEditor(kind, editing, accountID):
            TransactionEditorView(context: context, kind: kind, editing: editing, accountID: accountID)
        case let .accountEditor(editing):
            AccountEditorView(context: context, editing: editing)
        case let .budgetEditor(editing):
            BudgetEditorView(context: context, editing: editing)
        case let .goalEditor(editing):
            GoalEditorView(context: context, editing: editing)
        case let .contribution(goalID):
            ContributionView(context: context, goalID: goalID)
        case let .recurringEditor(editing, subscription):
            RecurringEditorView(context: context, editing: editing, subscription: subscription)
        case .editProfile:
            EditProfileView(context: context, services: scope.services)
        }
    }
}
