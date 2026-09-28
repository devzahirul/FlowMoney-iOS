public import Domain
public import Foundation
public import LedgerData

/// An in-memory "server" that behaves like the Supabase tables: upserts by primary key, stamps
/// `updatedAt` with its own clock, filters pulls by `updatedAt > since`, and can go offline on demand.
public actor FakeRemoteLedger: RemoteLedgerService {
    public private(set) var rows: [RecordKey: any LedgerRecord] = [:]
    public private(set) var pushCount = 0
    public private(set) var pushedRowCount = 0
    public var isOffline = false
    public var failure: SyncError?
    /// Runs in the middle of a push (after the request "left", before it returns) — to simulate edits
    /// made while a sync is in flight.
    private var duringPush: (@Sendable () async -> Void)?
    private var clock: Date

    public init(start: Date = Date(timeIntervalSince1970: 1_800_000_000)) {
        clock = start
    }

    public func setOffline(_ offline: Bool) {
        isOffline = offline
    }

    public func setFailure(_ error: SyncError?) {
        failure = error
    }

    public func setDuringPush(_ hook: (@Sendable () async -> Void)?) {
        duringPush = hook
    }

    /// Simulates a write from another device.
    public func serverWrite(_ record: some LedgerRecord) {
        var copy = record
        copy.updatedAt = tick()
        rows[copy.key] = copy
    }

    public func row<Record: LedgerRecord>(_ type: Record.Type, id: UUID) -> Record? {
        rows[RecordKey(kind: Record.kind, id: id)] as? Record
    }

    public func push(_ changes: ChangeSet) async throws(SyncError) {
        try check()
        pushCount += 1
        pushedRowCount += changes.count
        if let duringPush {
            await duringPush()
        }
        var all: [any LedgerRecord] = []
        all += changes.profiles as [any LedgerRecord]
        all += changes.accounts as [any LedgerRecord]
        all += changes.transactions as [any LedgerRecord]
        all += changes.budgets as [any LedgerRecord]
        all += changes.goals as [any LedgerRecord]
        all += changes.contributions as [any LedgerRecord]
        all += changes.recurringRules as [any LedgerRecord]
        for record in all {
            serverWrite(record)
        }
    }

    public func pull(since: Date?) async throws(SyncError) -> ChangeSet {
        try check()
        var changes = ChangeSet()
        for row in rows.values where since.map({ row.updatedAt > $0 }) ?? true {
            switch row {
            case let row as Profile: changes.profiles.append(row)
            case let row as Account: changes.accounts.append(row)
            case let row as LedgerTransaction: changes.transactions.append(row)
            case let row as Budget: changes.budgets.append(row)
            case let row as Goal: changes.goals.append(row)
            case let row as GoalContribution: changes.contributions.append(row)
            case let row as RecurringRule: changes.recurringRules.append(row)
            default: break
            }
        }
        return changes
    }

    private func check() throws(SyncError) {
        if isOffline {
            throw .offline
        }
        if let failure {
            throw failure
        }
    }

    private func tick() -> Date {
        clock = clock.addingTimeInterval(1)
        return clock
    }
}
