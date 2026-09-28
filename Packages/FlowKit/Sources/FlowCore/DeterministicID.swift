public import Foundation
import CryptoKit

public extension UUID {
    /// A name-based UUID (RFC 9562 v5 layout, SHA-256 truncated) — the same inputs always give the same ID.
    ///
    /// Recurring rules post their occurrences with `UUID(namespace: rule.id, name: "2026-03-01")`, so two
    /// devices that both auto-post March's rent produce the *same* row and the server upsert collapses them.
    init(namespace: UUID, name: String) {
        var hasher = SHA256()
        withUnsafeBytes(of: namespace.uuid) { hasher.update(bufferPointer: $0) }
        hasher.update(data: Data(name.utf8))
        var bytes = Array(hasher.finalize().prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        self = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
