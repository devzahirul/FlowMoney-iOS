public import Domain
public import Foundation
import Auth
import FlowCore

/// `AuthService` backed by Supabase Auth. Sessions live in the Keychain (via `KeychainLocalStorage`) and
/// refresh automatically; every SDK error is mapped to `Domain.AuthError` so features stay SDK-agnostic.
public final class SupabaseAuthService: AuthService {
    let client: AuthClient
    private let configuration: SupabaseConfiguration

    public var isConfigured: Bool {
        true
    }

    public init(configuration: SupabaseConfiguration) {
        self.configuration = configuration
        client = AuthClient(
            url: configuration.url.appending(path: "auth/v1"),
            headers: [
                "apikey": configuration.publishableKey,
                "Authorization": "Bearer \(configuration.publishableKey)",
            ],
            flowType: .pkce,
            storageKey: "flowmoney-auth",
            localStorage: KeychainLocalStorage(service: "com.lynkto.flowmoney.auth"),
            autoRefreshToken: true,
            emitLocalSessionAsInitialSession: true
        )
    }

    public func restoreSession() async -> AuthSession? {
        guard let session = client.currentSession else { return nil }
        return Self.map(session.user)
    }

    public func signIn(email: String, password: String) async throws(Domain.AuthError) -> AuthSession {
        do {
            let session = try await client.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
            return Self.map(session.user)
        } catch {
            throw Self.map(error)
        }
    }

    public func signUp(name: String, email: String, password: String) async throws(Domain.AuthError) -> SignUpResult {
        do {
            let trimmed = email.trimmingCharacters(in: .whitespaces)
            let response = try await client.signUp(
                email: trimmed,
                password: password,
                data: ["display_name": .string(name.trimmingCharacters(in: .whitespaces))],
                redirectTo: AuthRedirect.confirmEmail
            )
            switch response {
            case let .session(session): return .signedIn(Self.map(session.user))
            case .user: return .confirmationRequired(email: trimmed)
            }
        } catch {
            throw Self.map(error)
        }
    }

    public func sendPasswordReset(email: String) async throws(Domain.AuthError) {
        do {
            try await client.resetPasswordForEmail(email.trimmingCharacters(in: .whitespaces), redirectTo: AuthRedirect.resetPassword)
        } catch {
            throw Self.map(error)
        }
    }

    public func signOut() async {
        do {
            try await client.signOut(scope: .local)
        } catch {
            // Signing out must always succeed locally, even offline; the refresh token expires server-side.
            Log.auth.error("Remote sign-out failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func deleteAccount() async throws(Domain.AuthError) {
        do {
            let session = try await client.session
            var request = URLRequest(url: configuration.url.appending(path: "rest/v1/rpc/delete_my_account"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(SupabaseConfiguration.schema, forHTTPHeaderField: "Content-Profile")
            request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.httpBody = Data("{}".utf8)
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw Domain.AuthError.server("Couldn't delete the account. Please try again.")
            }
            try? await client.signOut(scope: .local)
        } catch {
            throw Self.map(error)
        }
    }

    public func handleAuthLink(_ url: URL) async throws(Domain.AuthError) -> AuthLink {
        do {
            // PKCE: the link carries a one-time code; the verifier was stored on this device when the email was requested.
            let session = try await client.session(from: url)
            let user = Self.map(session.user)
            return url.path().hasPrefix("/reset") ? .passwordRecovery(user) : .emailConfirmed(user)
        } catch {
            throw Self.map(error)
        }
    }

    public func updatePassword(_ newPassword: String) async throws(Domain.AuthError) {
        do {
            try await client.update(user: UserAttributes(password: newPassword))
        } catch {
            throw Self.map(error)
        }
    }

    public func sessionEnded() async -> AsyncStream<Void> {
        let changes = client.authStateChanges
        return AsyncStream { continuation in
            let task = Task {
                for await change in changes where change.event == .signedOut {
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Access token for PostgREST calls; refreshes it first if it's about to expire.
    func accessToken() async throws -> String {
        try await client.session.accessToken
    }

    // MARK: - Mapping

    static func map(_ user: User) -> AuthSession {
        let name: String? = if case let .string(value) = user.userMetadata["display_name"], !value.isEmpty {
            value
        } else {
            nil
        }
        return AuthSession(userID: user.id, email: user.email ?? "", displayName: name)
    }

    static func map(_ error: any Error) -> Domain.AuthError {
        if let error = error as? Domain.AuthError {
            return error
        }
        if let urlError = error as? URLError, urlError.isConnectivityProblem {
            return .offline
        }
        if case .pkceGrantCodeExchange = error as? Auth.AuthError {
            return .linkExpired
        }
        guard let error = error as? Auth.AuthError else {
            return .server("Something went wrong. Please try again.")
        }
        switch error.errorCode {
        case .invalidCredentials: return .invalidCredentials
        case .emailExists, .userAlreadyExists: return .emailAlreadyRegistered
        case .emailNotConfirmed: return .emailNotConfirmed
        case .weakPassword: return .weakPassword(error.message)
        case .otpExpired, .flowStateExpired, .flowStateNotFound, .badCodeVerifier: return .linkExpired
        case .overEmailSendRateLimit, .overRequestRateLimit: return .rateLimited
        default: return .server(error.message)
        }
    }
}

extension URLError {
    var isConnectivityProblem: Bool {
        [
            .notConnectedToInternet,
            .networkConnectionLost,
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dataNotAllowed,
            .internationalRoamingOff,
            .dnsLookupFailed,
        ].contains(code)
    }
}
