public import Domain
public import FlowCore
public import Foundation

/// The dependencies every feature screen needs, passed explicitly into view models (constructor injection:
/// no singletons, no service locator — a test builds one with fakes in a line).
public struct LedgerContext: Sendable {
    public let repository: any LedgerRepository
    public let calendar: Calendar
    public let now: @Sendable () -> Date
    /// Demo mode keeps everything on the device.
    public let isDemo: Bool

    public init(
        repository: any LedgerRepository,
        calendar: Calendar = .autoupdatingCurrent,
        isDemo: Bool = false,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.isDemo = isDemo
        self.now = now
    }

    public var currentMonth: YearMonth {
        YearMonth(now(), calendar: calendar)
    }
}

/// Base for screen view models: subscribes to the ledger once and recomputes derived state only when
/// the ledger actually changed (revision check), so unrelated re-renders cost nothing.
@MainActor
public protocol LedgerObserving: AnyObject {
    var context: LedgerContext { get }
    var lastRevision: Int? { get set }
    func update(with snapshot: LedgerSnapshot)
}

public extension LedgerObserving {
    /// Call from `.task {}` — the loop ends (and the subscription is released) when the view disappears.
    func observe() async {
        for await snapshot in await context.repository.snapshots() {
            guard snapshot.revision != lastRevision || lastRevision == nil else { continue }
            lastRevision = snapshot.revision
            update(with: snapshot)
        }
    }
}
