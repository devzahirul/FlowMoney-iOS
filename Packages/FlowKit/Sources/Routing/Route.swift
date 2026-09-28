public import Domain
public import Foundation
public import Observation

/// Every pushable screen. Features navigate with `NavigationLink(value: Route.x)` and never import each
/// other; `AppFeature` maps each case to a view. Adding a screen = one case + one line in the resolver.
public enum Route: Hashable, Sendable {
    case accounts
    case account(UUID)
    case transactions(TransactionFilter = .all)
    case transaction(UUID)
    case search
    case calendar
    case budgets
    case budget(UUID)
    case goals
    case goal(UUID)
    case subscriptions
    case recurring
    case cashFlow
    case spendingAnalytics
    case monthlyReport
    case netWorth
    case insights
    case notifications
    case settings
    case security
    case export
}

/// Modal forms. Presented by the root so any screen can open "Add expense" without owning the sheet.
public enum SheetRoute: Identifiable, Hashable, Sendable {
    case transactionEditor(kind: TransactionKind, editing: UUID? = nil, accountID: UUID? = nil)
    case accountEditor(editing: UUID? = nil)
    case budgetEditor(editing: UUID? = nil)
    case goalEditor(editing: UUID? = nil)
    case contribution(goalID: UUID)
    case recurringEditor(editing: UUID? = nil, subscription: Bool = false)
    case editProfile

    public var id: Self {
        self
    }
}

public enum AppTab: String, Hashable, Sendable, CaseIterable {
    case home, activity, plan, insights, profile
}

/// Navigation state for the whole app: one typed stack per tab plus the presented sheet.
/// Deep links and notification taps go through `open(_:)`, the same path as a user tap.
@MainActor
@Observable
public final class Router {
    public var selectedTab: AppTab = .home
    public var paths: [AppTab: [Route]] = [:]
    public var sheet: SheetRoute?

    public init() {}

    public func push(_ route: Route) {
        paths[selectedTab, default: []].append(route)
    }

    public func present(_ sheet: SheetRoute) {
        self.sheet = sheet
    }

    /// Re-tapping the selected tab pops to its root (standard iOS behaviour).
    public func select(_ tab: AppTab) {
        if tab == selectedTab {
            paths[tab] = []
        } else {
            selectedTab = tab
        }
    }

    /// Handles `flowmoney://` URLs (widgets, notifications, Home Screen quick actions).
    @discardableResult
    public func open(_ url: URL) -> Bool {
        guard url.scheme == "flowmoney" else { return false }
        let components = url.pathComponents.filter { $0 != "/" }
        switch url.host() {
        case "add-expense":
            present(.transactionEditor(kind: .expense))
        case "add-income":
            present(.transactionEditor(kind: .income))
        case "transaction":
            guard let id = components.first.flatMap(UUID.init(uuidString:)) else { return false }
            selectedTab = .activity
            paths[.activity] = [.transaction(id)]
        case "notifications":
            selectedTab = .home
            paths[.home] = [.notifications]
        case "subscriptions":
            selectedTab = .plan
            paths[.plan] = [.subscriptions]
        case "report":
            selectedTab = .insights
            paths[.insights] = [.monthlyReport]
        default:
            return false
        }
        return true
    }
}
