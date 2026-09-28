public import Domain
public import Foundation
import FlowCore

/// Offline-first implementation of `LedgerRepository`.
///
/// Writes land in local state and on disk immediately (the UI never waits for the network), are recorded
/// in an outbox, and a background sync pushes the outbox and pulls remote changes. Being an `actor` makes
/// every read-modify-write atomic without locks; `SyncEngine` logic lives here so a sync and a user edit
/// can never interleave inside a critical section.
public actor LocalLedgerRepository: LedgerRepository {
    public struct Configuration: Sendable {
        /// Wait after the last edit before syncing, so a burst of edits becomes one round-trip.
        public var syncDebounce: Duration = .seconds(1)
        /// Re-read this far behind the cursor: Postgres `now()` is the *transaction start* time, so a row can
        /// commit with an `updated_at` slightly older than rows already pulled. Merging is idempotent, so
        /// re-reading a minute of rows is cheap insurance against ever missing one.
        public var pullOverlap: TimeInterval = 60
        public var autoSync = true

        public init() {}
    }

    private var state: LedgerState
    private let persistence: any LedgerPersistence
    private let remote: (any RemoteLedgerService)?
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    private let configuration: Configuration

    private var snapshotCache: LedgerSnapshot?
    private var snapshotContinuations: [UUID: AsyncStream<LedgerSnapshot>.Continuation] = [:]
    private var statusContinuations: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
    private var status: SyncStatus
    private var isSyncing = false
    private var needsAnotherPass = false
    private var debounceTask: Task<Void, Never>?

    /// `async` so the disk read runs on the global executor, never on the caller's (main) actor.
    /// - Parameters:
    ///   - initialState: used when nothing is persisted yet (a new user, or the demo seed); only evaluated then.
    ///   - remote: `nil` for demo mode — the ledger then never leaves the device.
    public init(
        initialState: @autoclosure @Sendable () -> LedgerState,
        persistence: any LedgerPersistence,
        remote: (any RemoteLedgerService)?,
        configuration: Configuration = Configuration(),
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping @Sendable () -> Date = { Date() }
    ) async {
        let loaded: LedgerState?
        do {
            loaded = try persistence.load()
        } catch {
            // A corrupt file must not brick the app: start fresh; a remote user re-pulls everything.
            Log.store.error("Ledger file unreadable, starting fresh: \(error.localizedDescription, privacy: .public)")
            loaded = nil
        }
        state = loaded ?? initialState()
        self.persistence = persistence
        self.remote = remote
        self.configuration = configuration
        self.calendar = calendar
        self.now = now
        status = remote == nil
            ? .localOnly
            : SyncStatus(phase: .idle, lastSyncedAt: state.lastSyncedAt, pendingChanges: state.outbox.count)
    }

    // MARK: - Reads

    public func snapshots() -> AsyncStream<LedgerSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(of: LedgerSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        snapshotContinuations[id] = continuation
        continuation.yield(currentSnapshot())
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSnapshotSubscriber(id) }
        }
        return stream
    }

    public func currentSnapshot() -> LedgerSnapshot {
        if let snapshotCache, snapshotCache.revision == state.revision {
            return snapshotCache
        }
        let signpost = Log.signposter.beginInterval("ledger.snapshot")
        let snapshot = state.snapshot()
        Log.signposter.endInterval("ledger.snapshot", signpost)
        snapshotCache = snapshot
        return snapshot
    }

    public func syncStatus() -> AsyncStream<SyncStatus> {
        let (stream, continuation) = AsyncStream.makeStream(of: SyncStatus.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        statusContinuations[id] = continuation
        continuation.yield(status)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeStatusSubscriber(id) }
        }
        return stream
    }

    private func removeSnapshotSubscriber(_ id: UUID) {
        snapshotContinuations[id] = nil
    }

    private func removeStatusSubscriber(_ id: UUID) {
        statusContinuations[id] = nil
    }

    // MARK: - Writes

    public func perform(_ mutations: [LedgerMutation]) throws {
        var draft = state
        let timestamp = now()
        for mutation in mutations {
            try LedgerMutator.apply(mutation, to: &draft, at: timestamp)
        }
        guard draft != state else { return }
        draft.revision += 1
        try commit(draft)
        scheduleSync()
    }

    /// Posts due occurrences of recurring rules. Call on launch, on foreground and after a pull.
    public func postDueRecurringTransactions() throws {
        let due = RecurringPoster.dueTransactions(
            rules: Array(state.recurringRules.values),
            existingIDs: Set(state.transactions.keys),
            now: now(),
            calendar: calendar
        )
        guard !due.isEmpty else { return }
        Log.store.info("Posting \(due.count, privacy: .public) recurring transactions")
        try perform(due.map(LedgerMutation.saveTransaction))
    }

    /// Deletes the local copy (sign-out / account deletion).
    public func eraseLocalData() throws {
        debounceTask?.cancel()
        try persistence.erase()
        for continuation in snapshotContinuations.values {
            continuation.finish()
        }
        for continuation in statusContinuations.values {
            continuation.finish()
        }
        snapshotContinuations.removeAll()
        statusContinuations.removeAll()
    }

    private func commit(_ newState: LedgerState) throws {
        do {
            try persistence.save(newState)
        } catch {
            Log.store.fault("Ledger save failed: \(error.localizedDescription, privacy: .public)")
            throw LedgerError.invalid("Couldn't save your changes. Free up some storage and try again.")
        }
        state = newState
        publishSnapshot()
        updateStatus { $0.pendingChanges = newState.outbox.count }
    }

    private func publishSnapshot() {
        let snapshot = currentSnapshot()
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }

    private func updateStatus(_ change: (inout SyncStatus) -> Void) {
        var updated = status
        change(&updated)
        guard updated != status else { return }
        status = updated
        for continuation in statusContinuations.values {
            continuation.yield(updated)
        }
    }

    // MARK: - Sync

    private func scheduleSync() {
        guard remote != nil, configuration.autoSync else { return }
        debounceTask?.cancel()
        let delay = configuration.syncDebounce
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.synchronize()
        }
    }

    public func synchronize() async {
        guard let remote else { return }
        guard !isSyncing else {
            needsAnotherPass = true
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        let signpost = Log.signposter.beginInterval("ledger.sync")
        defer { Log.signposter.endInterval("ledger.sync", signpost) }

        repeat {
            needsAnotherPass = false
            updateStatus { $0.phase = .syncing }
            do {
                try await pushOutbox(to: remote)
                try await pull(from: remote)
                try? postDueRecurringTransactions()
                updateStatus {
                    $0.phase = .idle
                    $0.lastSyncedAt = state.lastSyncedAt
                    $0.pendingChanges = state.outbox.count
                }
            } catch {
                Log.sync.error("Sync failed: \(String(describing: error), privacy: .public)")
                updateStatus {
                    switch error {
                    case .offline: $0.phase = .offline
                    case .unauthorized: $0.phase = .failed("Your session expired. Please sign in again.")
                    case let .server(message): $0.phase = .failed(message)
                    }
                }
                return
            }
        } while needsAnotherPass
    }

    private func pushOutbox(to remote: any RemoteLedgerService) async throws(SyncError) {
        let pending = state.outbox
        guard !pending.isEmpty else { return }
        let changes = state.changeSet(for: pending.keys)
        Log.sync.info("Pushing \(changes.count, privacy: .public) rows")
        try await remote.push(changes)
        // The actor was re-entrant during `await`: only clear rows that weren't edited again meanwhile,
        // otherwise the newer edit would be silently dropped from the outbox.
        var next = state
        for (key, revision) in pending where next.outbox[key] == revision {
            next.outbox[key] = nil
        }
        try? commitSyncState(next)
    }

    private func pull(from remote: any RemoteLedgerService) async throws(SyncError) {
        let since = state.syncCursor.map { $0.addingTimeInterval(-configuration.pullOverlap) }
        let changes = try await remote.pull(since: since)
        var next = state
        let changed = next.merge(changes)
        if let latest = changes.latestUpdate {
            next.syncCursor = max(latest, next.syncCursor ?? .distantPast)
        }
        next.lastSyncedAt = now()
        Log.sync.info("Pulled \(changes.count, privacy: .public) rows, changed: \(changed, privacy: .public)")
        try? commitSyncState(next)
    }

    /// Persists sync bookkeeping; publishes only if data visible to screens changed.
    private func commitSyncState(_ next: LedgerState) throws {
        let visibleChange = next.revision != state.revision
        try persistence.save(next)
        state = next
        if visibleChange {
            publishSnapshot()
        }
        updateStatus { $0.pendingChanges = next.outbox.count }
    }

    // MARK: - Test hooks

    var pendingKeys: Set<RecordKey> {
        Set(state.outbox.keys)
    }

    var persistedState: LedgerState {
        state
    }
}
