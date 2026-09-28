public import Domain
public import Foundation
public import LedgerUI
public import Observation
import FlowCore

@MainActor
@Observable
public final class TransactionsViewModel: LedgerObserving {
    public var query = ""
    public var filter: TransactionFilter
    public private(set) var sections: [DaySection] = []
    public private(set) var isLoaded = false
    public private(set) var accountNames: [UUID: String] = [:]
    public var errorMessage: String?

    public let context: LedgerContext
    public var lastRevision: Int?
    private var snapshot: LedgerSnapshot?
    /// Filters to one account (Account detail reuses this screen model).
    private let accountID: UUID?

    public init(context: LedgerContext, filter: TransactionFilter = .all, accountID: UUID? = nil) {
        self.context = context
        self.filter = filter
        self.accountID = accountID
    }

    public func update(with snapshot: LedgerSnapshot) {
        self.snapshot = snapshot
        accountNames = snapshot.accounts.reduce(into: [:]) { $0[$1.id] = $1.name }
        applyQuery()
        isLoaded = true
    }

    /// Re-runs search + filter. Called on every (debounced) keystroke; pure and O(n).
    public func applyQuery() {
        guard let snapshot else { return }
        var results = TransactionQuery.search(query, filter: filter, in: snapshot)
        if let accountID {
            results = results.filter { $0.accountID == accountID }
        }
        sections = TransactionQuery.groupedByDay(results, calendar: context.calendar)
    }

    public var isEmpty: Bool {
        isLoaded && sections.isEmpty
    }

    public func delete(_ transaction: LedgerTransaction) async {
        do {
            try await context.repository.perform(.deleteTransaction(id: transaction.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refresh() async {
        await context.repository.synchronize()
    }
}
