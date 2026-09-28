import Domain
import FlowCore
import Foundation
import LocalAuthentication
import UserNotifications

/// Face ID / Touch ID via LocalAuthentication, falling back to the device passcode.
struct SystemDeviceAuthenticator: DeviceAuthenticator {
    func availableBiometry() -> BiometryKind {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        do {
            return try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            Log.app.info("Authentication failed: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
}

/// Mirrors `ReminderPlanner`'s list into UNUserNotificationCenter.
struct SystemReminderScheduler: ReminderScheduling {
    static let prefix = "flowmoney."

    func requestAuthorization() async -> Bool {
        await (try? UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    func isAuthorized() async -> Bool {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
    }

    func replaceAll(with reminders: [Reminder]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        for reminder in reminders {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            content.userInfo = ["url": reminder.id.hasPrefix("weekly") ? "flowmoney://report" : "flowmoney://subscriptions"]
            let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let request = UNNotificationRequest(
                identifier: Self.prefix + reminder.id,
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
            try? await center.add(request)
        }
    }
}

/// Used when no Supabase project is configured: the app offers demo mode only.
struct UnconfiguredAuthService: AuthService {
    var isConfigured: Bool {
        false
    }

    func restoreSession() async -> AuthSession? {
        nil
    }

    func signIn(email _: String, password _: String) async throws(AuthError) -> AuthSession {
        throw .notConfigured
    }

    func signUp(name _: String, email _: String, password _: String) async throws(AuthError) -> SignUpResult {
        throw .notConfigured
    }

    func sendPasswordReset(email _: String) async throws(AuthError) {
        throw .notConfigured
    }

    func signOut() async {}
    func deleteAccount() async throws(AuthError) {
        throw .notConfigured
    }

    func sessionEnded() async -> AsyncStream<Void> {
        AsyncStream { $0.finish() }
    }
}
