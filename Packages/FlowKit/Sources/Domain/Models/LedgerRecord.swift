public import Foundation

/// The kinds of rows that sync with the backend. Raw values are the Postgres table names.
public enum RecordKind: String, Codable, Sendable, CaseIterable, Hashable {
    case profile = "profiles"
    case account = "accounts"
    case transaction = "transactions"
    case budget = "budgets"
    case goal = "goals"
    case goalContribution = "goal_contributions"
    case recurringRule = "recurring_rules"
}

/// A syncable row. Every record has a client-generated UUID (so it can be created offline and upserted
/// idempotently), a server-authoritative `updatedAt`, and a soft-delete tombstone (`deletedAt`) so deletions
/// propagate to other devices through the same "changed since" query as edits.
public protocol LedgerRecord: Identifiable, Codable, Sendable, Hashable where ID == UUID {
    static var kind: RecordKind { get }
    var id: UUID { get }
    var updatedAt: Date { get set }
    var deletedAt: Date? { get set }
}

public extension LedgerRecord {
    var isDeleted: Bool {
        deletedAt != nil
    }

    var key: RecordKey {
        RecordKey(kind: Self.kind, id: id)
    }
}

/// Identifies one row across all tables.
public struct RecordKey: Hashable, Sendable, Codable, CustomStringConvertible {
    public let kind: RecordKind
    public let id: UUID

    public init(kind: RecordKind, id: UUID) {
        self.kind = kind
        self.id = id
    }

    public var description: String {
        "\(kind.rawValue)/\(id.uuidString.prefix(8))"
    }
}
