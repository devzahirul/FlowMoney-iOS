public import Domain
public import SwiftUI
import DesignSystem
import Observation

@MainActor
@Observable
public final class SetNewPasswordModel {
    public var password = ""
    public var confirmation = ""
    public private(set) var isSubmitting = false
    public private(set) var didUpdate = false
    public var errorMessage: String?
    private let auth: any AuthService

    public init(auth: any AuthService) {
        self.auth = auth
    }

    public var rules: [PasswordRule] {
        PasswordPolicy.rules(for: password)
    }

    public var matches: Bool {
        !confirmation.isEmpty && confirmation == password
    }

    public var canSubmit: Bool {
        PasswordPolicy.isValid(password) && matches && !isSubmitting
    }

    public func submit() async {
        guard canSubmit else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await auth.updatePassword(password)
            didUpdate = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Shown after the user taps the password-reset link in their email (they're already signed in by the link).
public struct SetNewPasswordView: View {
    @State private var model: SetNewPasswordModel
    @Environment(\.dismiss) private var dismiss

    public init(model: SetNewPasswordModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if model.didUpdate {
                        Label("Your password was updated.", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.income)
                        Button("Continue") { dismiss() }
                            .buttonStyle(.primary)
                    } else {
                        Text("Choose a new password for your account.").foregroundStyle(.secondary)
                        SecureFormField("New password", text: $model.password)
                            .textContentType(.newPassword)
                            .accessibilityIdentifier("reset.password")
                        SecureFormField("Confirm new password", text: $model.confirmation)
                            .textContentType(.newPassword)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(model.rules) { rule in
                                Label(rule.title, systemImage: rule.isSatisfied ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(rule.isSatisfied ? Theme.income : .secondary)
                            }
                            Label("Passwords match", systemImage: model.matches ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(model.matches ? Theme.income : .secondary)
                        }
                        .font(.footnote)
                        if let error = model.errorMessage {
                            ErrorBanner(error)
                        }
                        Button {
                            Task { await model.submit() }
                        } label: {
                            if model.isSubmitting {
                                ProgressView().tint(.white)
                            } else {
                                Text("Update Password")
                            }
                        }
                        .buttonStyle(.primary)
                        .disabled(!model.canSubmit)
                        .accessibilityIdentifier("reset.submit")
                    }
                }
                .padding(24)
            }
            .background(Theme.background)
            .navigationTitle("Set new password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !model.didUpdate {
                    ToolbarItem(placement: .cancellationAction) { Button("Later") { dismiss() } }
                }
            }
        }
        .interactiveDismissDisabled(!model.didUpdate)
    }
}
