public import SwiftUI
import AccountsFeature
import ActivityFeature
import AuthFeature
import DesignSystem
import Domain
import FlowCore
import HomeFeature
import InsightsFeature
import LedgerUI
import PlanFeature
import ProfileFeature
import Routing

/// The app's root view: picks onboarding, the lock screen or the main tabs from `AppModel.phase`.
public struct RootView: View {
    @State private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase

    public init(model: AppModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        ZStack {
            switch model.phase {
            case .launching:
                LaunchView()
            case .signedOut:
                OnboardingView(auth: model.auth, actions: model.authActions)
                    .transition(.opacity)
            case let .ready(scope):
                MainTabView(scope: scope, router: model.router)
                    .transition(.opacity)
            }
            if model.isLocked {
                LockView(biometry: model.biometry) { await model.unlock() }
                    .transition(.opacity)
                    .zIndex(2)
            } else if model.preferences.appLockEnabled, scenePhase != .active, model.isSignedIn {
                // Hides balances in the app switcher snapshot.
                PrivacyCover().zIndex(1)
            }
        }
        .animation(.smooth(duration: 0.25), value: model.isSignedIn)
        .animation(.smooth(duration: 0.2), value: model.isLocked)
        .environment(model.preferences)
        .environment(\.hideAmounts, model.preferences.hideAmounts)
        .preferredColorScheme(model.preferences.appearance.colorScheme)
        .tint(Theme.brand)
        .task { await model.start() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: Task { await model.sceneDidEnterBackground() }
            case .active: Task { await model.sceneDidBecomeActive() }
            default: break
            }
        }
        .onChange(of: model.preferences.remindersEnabled) { Task { await model.remindersPreferenceChanged() } }
        .onOpenURL { url in model.router.open(url) }
        .alert("Signed out", isPresented: Binding(get: { model.sessionMessage != nil }, set: {
            if !$0 {
                model.sessionMessage = nil
            }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.sessionMessage ?? "")
        }
    }
}

struct LaunchView: View {
    var body: some View {
        BrandMark(size: 88)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }
}

struct PrivacyCover: View {
    var body: some View {
        VStack(spacing: 12) {
            BrandMark(size: 72)
            Text("FlowMoney").font(.title2.bold())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial)
    }
}

// MARK: - Tabs

struct MainTabView: View {
    let scope: AppModel.SessionScope
    @Bindable var router: Router
    @State private var snapshotCurrency = CurrencyFormatObserver()

    var body: some View {
        TabView(selection: Binding(get: { router.selectedTab }, set: { router.select($0) })) {
            tab(.home, "Home", "house.fill") { HomeView(context: scope.context) }
            tab(.activity, "Activity", "list.bullet.rectangle.fill") { TransactionsView(context: scope.context) }
            tab(.plan, "Plan", "target") { PlanView(context: scope.context) }
            tab(.insights, "Insights", "chart.pie.fill") { InsightsHubView(context: scope.context) }
            tab(.profile, "Profile", "person.crop.circle.fill") { ProfileView(context: scope.context, services: scope.services) }
        }
        .environment(router)
        .environment(\.currency, snapshotCurrency.currency)
        .sheet(item: $router.sheet) { sheet in
            SheetDestination(sheet: sheet, scope: scope)
                .environment(router)
                .environment(\.currency, snapshotCurrency.currency)
        }
        .task { await snapshotCurrency.observe(scope.context.repository) }
    }

    private func tab(_ tab: AppTab, _ title: String, _ symbol: String, @ViewBuilder root: () -> some View) -> some View {
        NavigationStack(path: Binding(get: { router.paths[tab] ?? [] }, set: { router.paths[tab] = $0 })) {
            root()
                .navigationDestination(for: Route.self) { route in
                    RouteDestination(route: route, scope: scope)
                }
        }
        .tabItem { Label(title, systemImage: symbol) }
        .tag(tab)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
    }
}

/// Keeps one `CurrencyFormat` for the whole UI, rebuilt only when the profile's currency changes.
@MainActor
@Observable
final class CurrencyFormatObserver {
    private(set) var currency = CurrencyFormat.usd

    func observe(_ repository: any LedgerRepository) async {
        for await snapshot in await repository.snapshots() where snapshot.currency != currency {
            currency = snapshot.currency
        }
    }
}
