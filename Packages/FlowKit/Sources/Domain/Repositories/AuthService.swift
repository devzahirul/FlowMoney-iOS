public import Foundation

public struct AuthSession: Sendable, Equatable, Hashable {
    public let userID: UUID
    public let email: String
    public let displayName: String?

    public init(userID: UUID, email: String, displayName: String?) {
        self.userID = userID
        self.email = email
        self.displayName = displayName
    }
}

public enum SignUpResult: Sendable, Equatable {
    case signedIn(AuthSession)
    /// The project requires email confirmation; the user must tap the link before signing in.
    case confirmationRequired(email: String)
}

/// Auth failures the UI can explain. Backend-specific errors are mapped into these at the boundary,
/// so feature code never imports the backend SDK.
public enum AuthError: Error, Equatable, Sendable, LocalizedError {
    case invalidCredentials
    case emailAlreadyRegistered
    case emailNotConfirmed
    case weakPassword(String)
    case rateLimited
    case offline
    case notConfigured
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: "That email and password don't match."
        case .emailAlreadyRegistered: "An account with this email already exists. Try signing in."
        case .emailNotConfirmed: "Please confirm your email first — check your inbox for the link."
        case let .weakPassword(reason): reason
        case .rateLimited: "Too many attempts. Please wait a minute and try again."
        case .offline: "You're offline. Check your connection and try again."
        case .notConfigured: "Cloud sign-in isn't set up in this build. Try the demo instead."
        case let .server(message): message
        }
    }
}

public protocol AuthService: Sendable {
    /// Whether a real backend is configured (false in demo-only builds).
    var isConfigured: Bool { get }
    /// The persisted session, if any (read from the Keychain — no network).
    func restoreSession() async -> AuthSession?
    func signIn(email: String, password: String) async throws(AuthError) -> AuthSession
    func signUp(name: String, email: String, password: String) async throws(AuthError) -> SignUpResult
    func sendPasswordReset(email: String) async throws(AuthError)
    func signOut() async
    /// Permanently deletes the account and all its data server-side (App Store guideline 5.1.1(v)).
    func deleteAccount() async throws(AuthError)
    /// Emits `nil` when the session ends outside the app's control (revoked, refresh token expired).
    func sessionEnded() async -> AsyncStream<Void>
}
