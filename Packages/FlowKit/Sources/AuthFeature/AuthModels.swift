public import Domain
public import Observation
import Foundation

/// What the auth screens can ask the app shell to do. Closures keep AuthFeature ignorant of the shell.
public struct AuthActions: Sendable {
    public let signedIn: @MainActor @Sendable (AuthSession) async -> Void
    public let startDemo: @MainActor @Sendable () async -> Void

    public init(
        signedIn: @escaping @MainActor @Sendable (AuthSession) async -> Void,
        startDemo: @escaping @MainActor @Sendable () async -> Void
    ) {
        self.signedIn = signedIn
        self.startDemo = startDemo
    }
}

@MainActor
@Observable
public final class LoginModel {
    public var email = ""
    public var password = ""
    public private(set) var isSubmitting = false
    public var errorMessage: String?

    let auth: any AuthService
    private let actions: AuthActions

    public init(auth: any AuthService, actions: AuthActions) {
        self.auth = auth
        self.actions = actions
    }

    public var isConfigured: Bool {
        auth.isConfigured
    }

    public var canSubmit: Bool {
        EmailAddress.isValid(email) && !password.isEmpty && !isSubmitting
    }

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let session = try await auth.signIn(email: email, password: password)
            await actions.signedIn(session)
        } catch {
            errorMessage = error.localizedDescription
            password = ""
        }
    }
}

@MainActor
@Observable
public final class SignUpModel {
    public enum Phase: Equatable {
        case editing
        case awaitingConfirmation(email: String)
    }

    public var name = ""
    public var email = ""
    public var password = ""
    public var acceptedTerms = false
    public private(set) var phase = Phase.editing
    public private(set) var isSubmitting = false
    public var errorMessage: String?

    private let auth: any AuthService
    private let actions: AuthActions

    public init(auth: any AuthService, actions: AuthActions) {
        self.auth = auth
        self.actions = actions
    }

    public var passwordRules: [PasswordRule] {
        PasswordPolicy.rules(for: password)
    }

    public var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && EmailAddress.isValid(email)
            && PasswordPolicy.isValid(password) && acceptedTerms && !isSubmitting
    }

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            switch try await auth.signUp(name: name, email: email, password: password) {
            case let .signedIn(session): await actions.signedIn(session)
            case let .confirmationRequired(email): phase = .awaitingConfirmation(email: email)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

@MainActor
@Observable
public final class ForgotPasswordModel {
    public var email: String
    public private(set) var isSubmitting = false
    public private(set) var didSend = false
    public var errorMessage: String?
    private let auth: any AuthService

    public init(auth: any AuthService, email: String = "") {
        self.auth = auth
        self.email = email
    }

    public var canSubmit: Bool {
        EmailAddress.isValid(email) && !isSubmitting
    }

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await auth.sendPasswordReset(email: email)
            didSend = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
