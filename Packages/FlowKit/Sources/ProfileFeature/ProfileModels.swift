public import Domain
public import LedgerUI
public import Observation
import Foundation

/// Session facts and account-level actions the profile screens need from the app shell.
public struct AccountServices: Sendable {
    public let email: String
    public let isDemo: Bool
    public let backendHost: String?
    public let authenticator: any DeviceAuthenticator
    public let reminders: any ReminderScheduling
    public let signOut: @MainActor @Sendable () async -> Void
    public let deleteAccount: @MainActor @Sendable () async throws -> Void

    public init(
        email: String,
        isDemo: Bool,
        backendHost: String?,
        authenticator: any DeviceAuthenticator,
        reminders: any ReminderScheduling,
        signOut: @escaping @MainActor @Sendable () async -> Void,
        deleteAccount: @escaping @MainActor @Sendable () async throws -> Void
    ) {
        self.email = email
        self.isDemo = isDemo
        self.backendHost = backendHost
        self.authenticator = authenticator
        self.reminders = reminders
        self.signOut = signOut
        self.deleteAccount = deleteAccount
    }
}

@MainActor
@Observable
public final class ProfileModel: LedgerObserving {
    public private(set) var profile: Profile?
    public private(set) var accountCount = 0
    public private(set) var goalCount = 0
    public private(set) var transactionCount = 0
    public private(set) var syncStatus = SyncStatus.localOnly
    public var errorMessage: String?
    public private(set) var isWorking = false

    public let context: LedgerContext
    public let services: AccountServices
    public var lastRevision: Int?

    public init(context: LedgerContext, services: AccountServices) {
        self.context = context
        self.services = services
    }

    public func update(with snapshot: LedgerSnapshot) {
        profile = snapshot.profile
        accountCount = snapshot.accounts.count
        goalCount = snapshot.goals.count
        transactionCount = snapshot.transactions.count
    }

    public func observeSyncStatus() async {
        for await status in await context.repository.syncStatus() {
            syncStatus = status
        }
    }

    public func setCurrency(_ code: String) async {
        guard var profile, profile.currencyCode != code else { return }
        profile.currencyCode = code
        await save(profile)
    }

    public func rename(_ name: String) async -> Bool {
        guard var profile else { return false }
        profile.displayName = name
        return await save(profile)
    }

    @discardableResult
    private func save(_ profile: Profile) async -> Bool {
        do {
            try await context.repository.perform(.updateProfile(profile))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    public func syncNow() async {
        await context.repository.synchronize()
    }

    public func signOut() async {
        isWorking = true
        await services.signOut()
        isWorking = false
    }

    public func deleteAccount() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await services.deleteAccount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
