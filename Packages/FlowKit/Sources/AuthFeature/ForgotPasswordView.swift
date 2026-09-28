public import SwiftUI
import DesignSystem
import Domain

public struct ForgotPasswordView: View {
    @State private var model: ForgotPasswordModel
    @Environment(\.dismiss) private var dismiss

    public init(model: ForgotPasswordModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if model.didSend {
                    Label("If an account exists for \(model.email), a reset link is on its way.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.income)
                } else {
                    Text("Enter your email and we'll send you a link to reset your password.")
                        .foregroundStyle(.secondary)
                    FormField("Email address", text: $model.email, symbol: "envelope")
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let error = model.errorMessage {
                        ErrorBanner(error)
                    }
                    Button {
                        Task { await model.submit() }
                    } label: {
                        if model.isSubmitting {
                            ProgressView().tint(.white)
                        } else {
                            Text("Send reset link")
                        }
                    }
                    .buttonStyle(.primary)
                    .disabled(!model.canSubmit)
                }
                Spacer()
            }
            .padding(24)
            .background(Theme.background)
            .navigationTitle("Reset password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.didSend ? "Done" : "Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
