public import AuthFeature
public import Domain
public import LedgerUI
public import Observation
public import ProfileFeature
public import Routing
import FlowCore
import Foundation
import LedgerData

/// The app's top-level state machine: launching → signed out ⇄ signed in (cloud or demo), plus app lock.
///
/// Everything session-scoped (repository, router state, sheets) is created on sign-in and dropped on
/// sign-out, so one user's data can never leak into the next session.
@MainActor
@Observable
public final class AppModel {
    public enum Phase {
        case launching
        case signedOut
        case ready(SessionScope)
    }

    /// Objects that live exactly as long as one signed-in session.
    public struct SessionScope {
        public let context: LedgerContext
        public let services: AccountServices
        let repository: LocalLedgerRepository
        let userID: UUID
    }

    public private(set) var phase = Phase.launching
    public private(set) var isLocked = false
    public private(set) var router = Router()
    public let preferences: AppPreferences
    public var sessionMessage: String?

    let environment: AppEnvironment
    private var sessionTask: Task<Void, Never>?
    private var backgroundedAt: Date?

    static let demoKey = "session.demoActive"
    /// Coming back within this window doesn't re-prompt for Face ID (like banking apps).
    static let lockGracePeriod: TimeInterval = 30

    public init(environment: AppEnvironment) {
        self.environment = environment
        preferences = AppPreferences(defaults: environment.defaults)
    }

    public var authActions: AuthActions {
        AuthActions(
            signedIn: { [weak self] session in await self?.open(session: session) },
            startDemo: { [weak self] in await self?.openDemo() }
        )
    }

    public var auth: any AuthService {
        environment.auth
    }

    public var biometry: BiometryKind {
        environment.authenticator.availableBiometry()
    }

    // MARK: - Launch

    /// Restores the previous session from the Keychain / defaults — no network on the launch path.
    public func start() async {
        guard case .launching = phase else { return }
        let signpost = Log.signposter.beginInterval("app.restoreSession")
        defer { Log.signposter.endInterval("app.restoreSession", signpost) }
        if let session = await environment.auth.restoreSession() {
            await open(session: session)
        } else if environment.defaults.bool(forKey: Self.demoKey) {
            await openDemo()
        } else {
            phase = .signedOut
        }
        isLocked = preferences.appLockEnabled && isSignedIn
    }

    public var isSignedIn: Bool {
        if case .ready = phase {
            return true
        }
        return false
    }

    // MARK: - Sessions

    func open(session: AuthSession) async {
        let persistence = environment.makePersistence(session.userID)
        let repository = await LocalLedgerRepository(
            initialState: LedgerState(profile: Profile(id: session.userID, displayName: session.displayName ?? "")),
            persistence: persistence,
            remote: environment.makeRemote(session),
            configuration: environment.syncConfiguration,
            calendar: environment.calendar,
            now: environment.now
        )
        activate(repository: repository, userID: session.userID, email: session.email, isDemo: false)
        environment.defaults.set(false, forKey: Self.demoKey)
        sessionTask = Task { [weak self, auth = environment.auth] in
            for await _ in await auth.sessionEnded() {
                guard let self else { return }
                sessionMessage = "Your session ended. Please sign in again."
                await endSession(signOutRemotely: false)
            }
        }
    }

    func openDemo() async {
        let now = environment.now()
        let calendar = environment.calendar
        let repository = await LocalLedgerRepository(
            initialState: LedgerState(demo: DemoLedger.make(now: now, calendar: calendar)),
            persistence: environment.makePersistence(DemoLedger.userID),
            remote: nil,
            calendar: calendar,
            now: environment.now
        )
        activate(repository: repository, userID: DemoLedger.userID, email: "", isDemo: true)
        environment.defaults.set(true, forKey: Self.demoKey)
    }

    private func activate(repository: LocalLedgerRepository, userID: UUID, email: String, isDemo: Bool) {
        let context = LedgerContext(repository: repository, calendar: environment.calendar, isDemo: isDemo, now: environment.now)
        let services = AccountServices(
            email: email,
            isDemo: isDemo,
            backendHost: environment.backendHost,
            authenticator: environment.authenticator,
            reminders: environment.reminders,
            signOut: { [weak self] in await self?.endSession(signOutRemotely: true) },
            deleteAccount: { [weak self] in try await self?.deleteAccount() }
        )
        router = Router()
        phase = .ready(SessionScope(context: context, services: services, repository: repository, userID: userID))
        Task {
            try? await repository.postDueRecurringTransactions()
            await repository.synchronize()
        }
    }

    func endSession(signOutRemotely: Bool) async {
        guard case let .ready(scope) = phase else { return }
        sessionTask?.cancel()
        sessionTask = nil
        if signOutRemotely, !scope.services.isDemo {
            await environment.auth.signOut()
        }
        try? await scope.repository.eraseLocalData()
        await environment.reminders.replaceAll(with: [])
        preferences.reset()
        environment.defaults.set(false, forKey: Self.demoKey)
        isLocked = false
        router = Router()
        phase = .signedOut
    }

    func deleteAccount() async throws {
        try await environment.auth.deleteAccount()
        await endSession(signOutRemotely: false)
    }

    // MARK: - Lifecycle

    public func sceneDidEnterBackground() async {
        backgroundedAt = environment.now()
        guard case let .ready(scope) = phase else { return }
        await rescheduleReminders(scope)
    }

    public func sceneDidBecomeActive() async {
        if preferences.appLockEnabled, isSignedIn, let backgroundedAt,
           environment.now().timeIntervalSince(backgroundedAt) > Self.lockGracePeriod {
            isLocked = true
        }
        backgroundedAt = nil
        guard case let .ready(scope) = phase else { return }
        try? await scope.repository.postDueRecurringTransactions()
        await scope.repository.synchronize()
    }

    public func unlock() async {
        guard isLocked else { return }
        if await environment.authenticator.authenticate(reason: "Unlock FlowMoney") {
            isLocked = false
        }
    }

    /// BGAppRefreshTask handler: sync and post due bills while the app is in the background.
    public func backgroundRefresh() async {
        guard case let .ready(scope) = phase else { return }
        try? await scope.repository.postDueRecurringTransactions()
        await scope.repository.synchronize()
        await rescheduleReminders(scope)
    }

    public func remindersPreferenceChanged() async {
        guard case let .ready(scope) = phase else { return }
        await rescheduleReminders(scope)
    }

    private func rescheduleReminders(_ scope: SessionScope) async {
        guard preferences.remindersEnabled, await environment.reminders.isAuthorized() else {
            await environment.reminders.replaceAll(with: [])
            return
        }
        let snapshot = await scope.repository.currentSnapshot()
        let reminders = ReminderPlanner.reminders(for: snapshot, now: environment.now(), calendar: environment.calendar)
        await environment.reminders.replaceAll(with: reminders)
    }
}
