public import Domain
public import Foundation
public import LedgerData
import FlowCore
import SupabaseBackend

/// Every outside-world dependency of the app, in one place. `live()` wires real services; tests and UI tests
/// build their own — nothing else in the app reaches for a singleton.
public struct AppEnvironment: Sendable {
    public var auth: any AuthService
    /// Builds the sync backend for a signed-in user (nil = local only).
    public var makeRemote: @Sendable (AuthSession) -> (any RemoteLedgerService)?
    public var makePersistence: @Sendable (UUID) -> any LedgerPersistence
    public var authenticator: any DeviceAuthenticator
    public var reminders: any ReminderScheduling
    public var backendHost: String?
    public var calendar: Calendar
    public var now: @Sendable () -> Date
    /// `UserDefaults` suite (nil = standard). Stored by name because `UserDefaults` isn't `Sendable`.
    public var defaultsSuite: String?
    public var defaults: UserDefaults {
        defaultsSuite.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public var syncConfiguration: LocalLedgerRepository.Configuration

    public init(
        auth: any AuthService,
        makeRemote: @escaping @Sendable (AuthSession) -> (any RemoteLedgerService)?,
        makePersistence: @escaping @Sendable (UUID) -> any LedgerPersistence,
        authenticator: any DeviceAuthenticator,
        reminders: any ReminderScheduling,
        backendHost: String?,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() },
        defaultsSuite: String? = nil,
        syncConfiguration: LocalLedgerRepository.Configuration = .init()
    ) {
        self.auth = auth
        self.makeRemote = makeRemote
        self.makePersistence = makePersistence
        self.authenticator = authenticator
        self.reminders = reminders
        self.backendHost = backendHost
        self.calendar = calendar
        self.now = now
        self.defaultsSuite = defaultsSuite
        self.syncConfiguration = syncConfiguration
    }

    /// Production wiring. Supabase is used only when Info.plist carries a project URL + key.
    public static func live(bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> AppEnvironment {
        // UI tests: demo-only, in-memory, deterministic.
        if processInfo.arguments.contains("-uiTesting") {
            return uiTesting(dark: processInfo.arguments.contains("-uiDark"))
        }
        let persistence: @Sendable (UUID) -> any LedgerPersistence = { FileLedgerPersistence(userID: $0) }
        guard let configuration = SupabaseConfiguration(infoDictionary: bundle.infoDictionary) else {
            Log.app.info("No Supabase configuration — demo mode only")
            return AppEnvironment(
                auth: UnconfiguredAuthService(),
                makeRemote: { _ in nil },
                makePersistence: persistence,
                authenticator: SystemDeviceAuthenticator(),
                reminders: SystemReminderScheduler(),
                backendHost: nil
            )
        }
        let auth = SupabaseAuthService(configuration: configuration)
        let remote = SupabaseLedgerService(configuration: configuration, auth: auth)
        return AppEnvironment(
            auth: auth,
            makeRemote: { _ in remote },
            makePersistence: persistence,
            authenticator: SystemDeviceAuthenticator(),
            reminders: SystemReminderScheduler(),
            backendHost: configuration.host
        )
    }

    static func uiTesting(dark: Bool) -> AppEnvironment {
        let suite = UserDefaults(suiteName: "flowmoney.uitests")
        suite?.removePersistentDomain(forName: "flowmoney.uitests")
        if dark {
            suite?.set("dark", forKey: "pref.appearance")
        }
        return AppEnvironment(
            auth: UnconfiguredAuthService(),
            makeRemote: { _ in nil },
            makePersistence: { _ in InMemoryLedgerPersistence() },
            authenticator: SystemDeviceAuthenticator(),
            reminders: SystemReminderScheduler(),
            backendHost: nil,
            defaultsSuite: "flowmoney.uitests"
        )
    }
}
