public import SwiftUI
import DesignSystem
import Domain

/// Screen 2 — email + password sign-in.
public struct LoginView: View {
    @State private var model: LoginModel
    @State private var showsReset = false
    @FocusState private var focus: Field?
    let onSignUp: () -> Void

    private enum Field { case email, password }

    public init(model: LoginModel, onSignUp: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onSignUp = onSignUp
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    BrandMark(size: 56)
                    Text("Welcome back").font(.largeTitle.bold())
                    Text("Sign in to continue your financial journey")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                VStack(spacing: 14) {
                    FormField("Email address", text: $model.email, symbol: "envelope")
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .accessibilityIdentifier("login.email")
                    SecureFormField("Password", text: $model.password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await model.submit() } }
                        .accessibilityIdentifier("login.password")
                    HStack {
                        Spacer()
                        Button("Forgot password?") { showsReset = true }
                            .font(.footnote.weight(.semibold))
                    }
                }

                if let error = model.errorMessage {
                    ErrorBanner(error)
                }

                Button {
                    focus = nil
                    Task { await model.submit() }
                } label: {
                    if model.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Text("Sign In")
                    }
                }
                .buttonStyle(.primary)
                .disabled(!model.canSubmit)
                .accessibilityIdentifier("login.submit")

                HStack(spacing: 4) {
                    Text("Don't have an account?").foregroundStyle(.secondary)
                    Button("Sign Up", action: onSignUp).fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsReset) {
            ForgotPasswordView(model: ForgotPasswordModel(auth: model.auth, email: model.email))
        }
        .sensoryFeedback(.error, trigger: model.errorMessage) { _, new in new != nil }
    }
}
