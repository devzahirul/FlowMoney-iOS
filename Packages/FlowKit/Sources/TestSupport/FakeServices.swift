public import Domain
import Foundation

/// Scriptable `AuthService`: set `nextResult`/`signUpResult` and inspect `calls`.
public actor FakeAuthService: AuthService {
    public nonisolated let isConfigured: Bool
    public var session: AuthSession?
    public var signInResult: Result<AuthSession, AuthError> = .failure(.invalidCredentials)
    public var signUpResult: Result<SignUpResult, AuthError> = .failure(.server("not scripted"))
    public private(set) var calls: [String] = []
    private var endedContinuation: AsyncStream<Void>.Continuation?

    public init(isConfigured: Bool = true, session: AuthSession? = nil) {
        self.isConfigured = isConfigured
        self.session = session
    }

    public func script(signIn: Result<AuthSession, AuthError>) {
        signInResult = signIn
    }

    public func script(signUp: Result<SignUpResult, AuthError>) {
        signUpResult = signUp
    }

    public func restoreSession() async -> AuthSession? {
        calls.append("restore")
        return session
    }

    public func signIn(email: String, password _: String) async throws(AuthError) -> AuthSession {
        calls.append("signIn:\(email)")
        return try signInResult.get()
    }

    public func signUp(name _: String, email: String, password _: String) async throws(AuthError) -> SignUpResult {
        calls.append("signUp:\(email)")
        return try signUpResult.get()
    }

    public func sendPasswordReset(email: String) async throws(AuthError) {
        calls.append("reset:\(email)")
    }

    public func signOut() async {
        calls.append("signOut")
        session = nil
    }

    public func deleteAccount() async throws(AuthError) {
        calls.append("delete")
        session = nil
    }

    public func sessionEnded() async -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        endedContinuation = continuation
        return stream
    }

    /// Simulates the server revoking the session.
    public func endSessionRemotely() {
        endedContinuation?.yield()
    }
}

public struct FakeAuthenticator: DeviceAuthenticator {
    public let succeeds: Bool
    public init(succeeds: Bool = true) {
        self.succeeds = succeeds
    }

    public func availableBiometry() -> BiometryKind {
        .faceID
    }

    public func authenticate(reason _: String) async -> Bool {
        succeeds
    }
}

public actor FakeReminderScheduler: ReminderScheduling {
    public private(set) var scheduled: [Reminder] = []
    public var authorized: Bool

    public init(authorized: Bool = true) {
        self.authorized = authorized
    }

    public func requestAuthorization() async -> Bool {
        authorized
    }

    public func isAuthorized() async -> Bool {
        authorized
    }

    public func replaceAll(with reminders: [Reminder]) async {
        scheduled = reminders
    }
}
