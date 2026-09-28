public import os

/// One `Logger` per subsystem area. Messages use privacy annotations, so amounts, emails and merchants are
/// redacted in release logs (`os_log` marks interpolations `private` by default).
public enum Log {
    public static let subsystem = "com.lynkto.flowmoney"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let auth = Logger(subsystem: subsystem, category: "auth")
    public static let sync = Logger(subsystem: subsystem, category: "sync")
    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let ui = Logger(subsystem: subsystem, category: "ui")

    /// Points of interest for Instruments (launch, first frame, sync) — see docs/PERFORMANCE.md.
    public static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}
