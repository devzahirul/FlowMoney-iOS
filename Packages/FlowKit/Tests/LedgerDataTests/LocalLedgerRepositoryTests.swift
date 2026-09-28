import Domain
import FlowCore
import Foundation
@testable import LedgerData
import Testing
import TestSupport

@Suite("LocalLedgerRepository — local writes")
struct LocalWriteTests {
    let persistence = InMemoryLedgerPersistence()

    func makeRepository(remote: (any RemoteLedgerService)? = nil) async -> LocalLedgerRepository {
        var configuration = LocalLedgerRepository.Configuration()
        configuration.autoSync = false
        var state = LedgerState(profile: Fixture.profile())
        state.accounts[Fixture.checkingID] = Fixture.account()
        let initialState = state
        return await LocalLedgerRepository(
            initialState: initialState,
            persistence: persistence,
            remote: remote,
            configuration: configuration,
            calendar: TestCalendar.utc,
            now: { TestCalendar.date(2026, 3, 10) }
        )
    }

    @Test("A write is persisted and streamed to subscribers immediately")
    func writeIsStreamed() async throws {
        let repository = await makeRepository()
        var snapshots = await repository.snapshots().makeAsyncIterator()
        #expect(await snapshots.next()?.transactions.isEmpty == true)

        try await repository.perform(.saveTransaction(Fixture.expense(.dollars(5), on: TestCalendar.date(2026, 3, 9))))

        #expect(await snapshots.next()?.transactions.count == 1)
        #expect(persistence.state?.transactions.count == 1)
    }

    @Test("Invalid writes are rejected atomically — nothing from the batch is applied")
    func atomicBatch() async throws {
        let repository = await makeRepository()
        let valid = Fixture.expense(.dollars(5), on: TestCalendar.date(2026, 3, 9))
        let invalid = Fixture.expense(.zero, on: TestCalendar.date(2026, 3, 9))
        await #expect(throws: LedgerError.invalid("Enter an amount greater than zero.")) {
            try await repository.perform([.saveTransaction(valid), .saveTransaction(invalid)])
        }
        #expect(await repository.currentSnapshot().transactions.isEmpty)
        #expect(persistence.saveCount == 0)
    }

    @Test("Deleting an account tombstones its transactions and rules too")
    func cascadeDelete() async throws {
        let repository = await makeRepository()
        let transaction = Fixture.expense(.dollars(5), on: TestCalendar.date(2026, 3, 9))
        try await repository.perform([
            .saveTransaction(transaction),
            .saveRecurringRule(Fixture.rule(start: TestCalendar.date(2026, 1, 1))),
        ])
        try await repository.perform(.deleteAccount(id: Fixture.checkingID))

        let snapshot = await repository.currentSnapshot()
        #expect(snapshot.accounts.isEmpty && snapshot.transactions.isEmpty && snapshot.recurringRules.isEmpty)
        let stored = await repository.persistedState
        #expect(stored.transactions[transaction.id]?.deletedAt != nil, "tombstone kept so the delete syncs")
        #expect(await repository.pendingKeys.contains(RecordKey(kind: .transaction, id: transaction.id)))
    }

    @Test("Saving a second budget for a category replaces the first instead of duplicating")
    func oneBudgetPerCategory() async throws {
        let repository = await makeRepository()
        try await repository.perform(.saveBudget(Fixture.budget(.food, limit: .dollars(300))))
        try await repository.perform(.saveBudget(Fixture.budget(.food, limit: .dollars(450))))
        let budgets = await repository.currentSnapshot().budgets
        #expect(budgets.count == 1)
        #expect(budgets.first?.limit == .dollars(450))
    }

    @Test("Re-saving an unchanged record is a no-op (no disk write, no sync)")
    func unchangedSaveIsNoop() async throws {
        let repository = await makeRepository()
        let transaction = Fixture.expense(.dollars(5), on: TestCalendar.date(2026, 3, 9))
        try await repository.perform(.saveTransaction(transaction))
        let writes = persistence.saveCount
        try await repository.perform(.saveTransaction(transaction))
        #expect(persistence.saveCount == writes)
    }

    @Test("Due recurring transactions are posted once, even if asked repeatedly")
    func recurringPostingIsIdempotent() async throws {
        let repository = await makeRepository()
        try await repository.perform(.saveRecurringRule(Fixture.rule(
            start: TestCalendar.date(2026, 3, 1),
            createdAt: TestCalendar.date(2026, 1, 1)
        )))
        try await repository.postDueRecurringTransactions()
        try await repository.postDueRecurringTransactions()
        #expect(await repository.currentSnapshot().transactions.count == 1)
    }

    @Test("A corrupt or missing file falls back to the initial state")
    func startsFreshWithoutFile() async {
        let repository = await makeRepository()
        #expect(await repository.currentSnapshot().accounts.count == 1)
    }
}

@Suite("LocalLedgerRepository — sync")
struct SyncTests {
    let remote = FakeRemoteLedger()
    let persistence = InMemoryLedgerPersistence()

    func makeRepository(persistence: InMemoryLedgerPersistence? = nil) async -> LocalLedgerRepository {
        var configuration = LocalLedgerRepository.Configuration()
        configuration.autoSync = false
        var state = LedgerState(profile: Fixture.profile())
        state.accounts[Fixture.checkingID] = Fixture.account()
        state.outbox[RecordKey(kind: .account, id: Fixture.checkingID)] = 1
        let initialState = state
        return await LocalLedgerRepository(
            initialState: initialState,
            persistence: persistence ?? self.persistence,
            remote: remote,
            configuration: configuration,
            calendar: TestCalendar.utc,
            now: { TestCalendar.date(2026, 3, 10) }
        )
    }

    @Test("Ten offline edits to one row upload as a single upsert of the latest version")
    func coalescesOfflineEdits() async throws {
        let repository = await makeRepository()
        await repository.synchronize()
        let pushesBefore = await remote.pushedRowCount
        await remote.setOffline(true)

        var transaction = Fixture.expense(.dollars(1), on: TestCalendar.date(2026, 3, 9))
        for cents in 1 ... 10 {
            transaction.amount = Money(minorUnits: Int64(cents) * 100)
            try await repository.perform(.saveTransaction(transaction))
        }
        await repository.synchronize()
        #expect(await repository.syncStatus().first { _ in true }?.phase == .offline)

        await remote.setOffline(false)
        await repository.synchronize()
        #expect(await remote.pushedRowCount - pushesBefore == 1)
        #expect(await remote.row(LedgerTransaction.self, id: transaction.id)?.amount == .dollars(10))
        #expect(await repository.pendingKeys.isEmpty)
    }

    @Test("An edit made while a push is in flight is not lost")
    func editDuringPushSurvives() async throws {
        let repository = await makeRepository()
        let transaction = Fixture.expense(.dollars(1), on: TestCalendar.date(2026, 3, 9))
        try await repository.perform(.saveTransaction(transaction))

        var edited = transaction
        edited.amount = .dollars(99)
        await remote.setDuringPush { [edited] in
            try? await repository.perform(.saveTransaction(edited))
        }
        await repository.synchronize()
        await remote.setDuringPush(nil)

        let key = RecordKey(kind: .transaction, id: transaction.id)
        #expect(await repository.currentSnapshot().transactions.first?.amount == .dollars(99))
        await repository.synchronize()
        #expect(await remote.row(LedgerTransaction.self, id: transaction.id)?.amount == .dollars(99))
        #expect(await !repository.pendingKeys.contains(key))
    }

    @Test("Changes from another device are pulled, and deletes propagate as tombstones")
    func pullsRemoteChanges() async {
        let repository = await makeRepository()
        await repository.synchronize()

        let fromPhone = Fixture.expense(.dollars(7), on: TestCalendar.date(2026, 3, 9), merchant: "Phone")
        await remote.serverWrite(fromPhone)
        await repository.synchronize()
        #expect(await repository.currentSnapshot().transactions.map(\.merchant) == ["Phone"])

        var deleted = fromPhone
        deleted.deletedAt = TestCalendar.date(2026, 3, 10)
        await remote.serverWrite(deleted)
        await repository.synchronize()
        #expect(await repository.currentSnapshot().transactions.isEmpty)
    }

    @Test("A pending local edit wins over an older server copy")
    func localPendingWins() async throws {
        let repository = await makeRepository()
        let transaction = Fixture.expense(.dollars(1), on: TestCalendar.date(2026, 3, 9))
        try await repository.perform(.saveTransaction(transaction))
        await repository.synchronize()

        await remote.setOffline(true)
        var local = transaction
        local.merchant = "Local edit"
        try await repository.perform(.saveTransaction(local))

        var server = transaction
        server.merchant = "Other device"
        await remote.serverWrite(server)
        await remote.setOffline(false)
        await repository.synchronize()

        #expect(await repository.currentSnapshot().transactions.first?.merchant == "Local edit")
        #expect(await remote.row(LedgerTransaction.self, id: transaction.id)?.merchant == "Local edit")
    }

    @Test("A fresh device pulls everything and survives a relaunch from disk")
    func freshDeviceAndRelaunch() async throws {
        let first = await makeRepository()
        try await first.perform(.saveTransaction(Fixture.expense(.dollars(3), on: TestCalendar.date(2026, 3, 9))))
        await first.synchronize()

        let secondDisk = InMemoryLedgerPersistence()
        let second = await makeRepository(persistence: secondDisk)
        await second.synchronize()
        #expect(await second.currentSnapshot().transactions.count == 1)

        let relaunched = await makeRepository(persistence: secondDisk)
        #expect(await relaunched.currentSnapshot().transactions.count == 1)
        #expect(await relaunched.persistedState.syncCursor != nil)
    }

    @Test("Expired session surfaces as a failed status the UI can act on")
    func unauthorized() async {
        let repository = await makeRepository()
        await remote.setFailure(.unauthorized)
        await repository.synchronize()
        let status = await repository.syncStatus().first { _ in true }
        #expect(status?.phase == .failed("Your session expired. Please sign in again."))
        #expect(status?.pendingChanges == 1)
    }
}
