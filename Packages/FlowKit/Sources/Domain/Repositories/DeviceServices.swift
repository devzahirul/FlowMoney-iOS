public import Foundation

public enum BiometryKind: Sendable, Equatable {
    case none, touchID, faceID, opticID

    public var title: String {
        switch self {
        case .none: "Passcode"
        case .touchID: "Touch ID"
        case .faceID: "Face ID"
        case .opticID: "Optic ID"
        }
    }
}

/// Face ID / Touch ID / passcode gate for the app lock.
public protocol DeviceAuthenticator: Sendable {
    func availableBiometry() -> BiometryKind
    /// `true` when the owner authenticated. Falls back to the device passcode.
    func authenticate(reason: String) async -> Bool
}

/// A local reminder the app wants scheduled (subscription renewals, weekly summary).
public struct Reminder: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let body: String
    public let fireDate: Date

    public init(id: String, title: String, body: String, fireDate: Date) {
        self.id = id
        self.title = title
        self.body = body
        self.fireDate = fireDate
    }
}

public protocol ReminderScheduling: Sendable {
    /// Asks for notification permission. Call only in context (from the Notifications toggle), never at launch.
    func requestAuthorization() async -> Bool
    func isAuthorized() async -> Bool
    /// Replaces every pending FlowMoney reminder with `reminders`.
    func replaceAll(with reminders: [Reminder]) async
}
