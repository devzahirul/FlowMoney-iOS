public import Foundation

/// Every write the app can make. One enum (rather than a method per entity) keeps the repository surface
/// small, lets a screen apply several changes atomically, and makes writes easy to log and assert in tests.
public enum LedgerMutation: Sendable, Hashable {
    case saveAccount(Account)
    /// Also removes the account's transactions and recurring rules.
    case deleteAccount(id: UUID)
    case saveTransaction(LedgerTransaction)
    case deleteTransaction(id: UUID)
    case saveBudget(Budget)
    case deleteBudget(id: UUID)
    case saveGoal(Goal)
    /// Also removes the goal's contributions.
    case deleteGoal(id: UUID)
    case saveContribution(GoalContribution)
    case deleteContribution(id: UUID)
    case saveRecurringRule(RecurringRule)
    case deleteRecurringRule(id: UUID)
    case updateProfile(Profile)
}

public enum LedgerError: Error, Equatable, Sendable, LocalizedError {
    case invalid(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case let .invalid(reason): reason
        case .notFound: "That item no longer exists."
        }
    }
}

public struct SyncStatus: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        /// Demo mode: nothing leaves the device.
        case localOnly
        case idle
        case syncing
        case offline
        case failed(String)
    }

    public var phase: Phase
    public var lastSyncedAt: Date?
    /// Local changes not yet confirmed by the server.
    public var pendingChanges: Int

    public init(phase: Phase, lastSyncedAt: Date? = nil, pendingChanges: Int = 0) {
        self.phase = phase
        self.lastSyncedAt = lastSyncedAt
        self.pendingChanges = pendingChanges
    }

    public static let localOnly = SyncStatus(phase: .localOnly)
}

/// The single source of truth for the signed-in user's data.
///
/// Reads are streams, not fetches: a screen subscribes once and re-renders whenever *any* screen (or a
/// sync from another device) changes the ledger, so there is no "pull to refresh after editing" code anywhere.
public protocol LedgerRepository: Sendable {
    /// Emits the current snapshot immediately, then every change. Ends when the caller's task is cancelled.
    func snapshots() async -> AsyncStream<LedgerSnapshot>
    /// Applies the mutations atomically (all or nothing), persists them, and schedules a sync.
    func perform(_ mutations: [LedgerMutation]) async throws
    func syncStatus() async -> AsyncStream<SyncStatus>
    /// Pushes pending changes and pulls remote ones now (e.g. pull-to-refresh, app foregrounded).
    func synchronize() async
    /// The latest snapshot without subscribing (exports, one-off reads).
    func currentSnapshot() async -> LedgerSnapshot
}

public extension LedgerRepository {
    func perform(_ mutation: LedgerMutation) async throws {
        try await perform([mutation])
    }
}
