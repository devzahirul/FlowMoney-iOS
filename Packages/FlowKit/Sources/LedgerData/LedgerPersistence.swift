public import Foundation
import FlowCore

/// Where `LedgerState` lives between launches.
public protocol LedgerPersistence: Sendable {
    func load() throws -> LedgerState?
    func save(_ state: LedgerState) throws
    func erase() throws
}

/// One JSON file per user in Application Support, written atomically and encrypted at rest with
/// Data Protection (`completeUntilFirstUserAuthentication`, so background refresh can still read it).
///
/// Why a file and not Core Data / SwiftData: the whole ledger of a personal user is a few thousand rows;
/// a single snapshot file loads in milliseconds, has no migration machinery, and keeps the store a plain
/// value type that is trivial to test. ADR-0003 records the threshold at which we'd move to SQLite.
public struct FileLedgerPersistence: LedgerPersistence {
    public let url: URL

    public init(userID: UUID, directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appending(path: "Ledger", directoryHint: .isDirectory).appending(path: "\(userID.uuidString.lowercased()).json")
    }

    public func load() throws -> LedgerState? {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        let signpost = Log.signposter.beginInterval("ledger.load")
        defer { Log.signposter.endInterval("ledger.load", signpost) }
        let state = try JSONDecoder().decode(LedgerState.self, from: Data(contentsOf: url, options: .mappedIfSafe))
        // A file from a newer app version is not guessed at: start clean and re-pull from the server.
        guard state.schemaVersion <= LedgerState.currentSchemaVersion else { return nil }
        return state
    }

    public func save(_ state: LedgerState) throws {
        let data = try JSONEncoder().encode(state)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
            try data.write(to: url, options: .atomic)
        #endif
    }

    public func erase() throws {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

/// For tests and previews.
public final class InMemoryLedgerPersistence: LedgerPersistence, @unchecked Sendable {
    // @unchecked: all access goes through `lock`.
    private let lock = NSLock()
    private var stored: LedgerState?
    private var writes = 0

    public init(_ state: LedgerState? = nil) {
        stored = state
    }

    public func load() throws -> LedgerState? {
        lock.withLock { stored }
    }

    public func save(_ state: LedgerState) throws {
        lock.withLock {
            stored = state
            writes += 1
        }
    }

    public func erase() throws {
        lock.withLock { stored = nil }
    }

    public var saveCount: Int {
        lock.withLock { writes }
    }

    public var state: LedgerState? {
        lock.withLock { stored }
    }
}
