public import SwiftUI
import DesignSystem
import Domain

/// Screen 3 — create an account, with the live password checklist.
public struct SignUpView: View {
    @State private var model: SignUpModel
    @FocusState private var focus: Field?
    let onSignIn: () -> Void

    private enum Field { case name, email, password }

    public init(model: SignUpModel, onSignIn: @escaping () -> Void) {
        _model = State(initialValue: model)
        self.onSignIn = onSignIn
    }

    public var body: some View {
        ScrollView {
            switch model.phase {
            case .editing: form
            case let .awaitingConfirmation(email): confirmation(email)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Create your account").font(.largeTitle.bold())
                Text("Start your journey to a brighter financial future").foregroundStyle(.secondary)
            }

            VStack(spacing: 14) {
                FormField("Full name", text: $model.name, symbol: "person")
                    .textContentType(.name)
                    .focused($focus, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focus = .email }
                    .accessibilityIdentifier("signup.name")
                FormField("Email address", text: $model.email, symbol: "envelope")
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
                    .accessibilityIdentifier("signup.email")
                SecureFormField("Password", text: $model.password)
                    .textContentType(.newPassword)
                    .focused($focus, equals: .password)
                    .accessibilityIdentifier("signup.password")
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(model.passwordRules) { rule in
                    Label(rule.title, systemImage: rule.isSatisfied ? "checkmark.circle.fill" : "circle")
                        .font(.footnote)
                        .foregroundStyle(rule.isSatisfied ? Theme.income : .secondary)
                        .accessibilityValue(rule.isSatisfied ? "met" : "not met")
                }
            }
            .animation(.snappy, value: model.passwordRules)

            Toggle(isOn: $model.acceptedTerms) {
                Text("I agree to the [Terms of Service](https://flowmoney.app/terms) and [Privacy Policy](https://flowmoney.app/privacy)")
                    .font(.footnote)
            }
            .toggleStyle(CheckboxToggleStyle())
            .accessibilityIdentifier("signup.terms")

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
                    Text("Create Account")
                }
            }
            .buttonStyle(.primary)
            .disabled(!model.canSubmit)
            .accessibilityIdentifier("signup.submit")

            HStack(spacing: 4) {
                Text("Already have an account?").foregroundStyle(.secondary)
                Button("Sign In", action: onSignIn).fontWeight(.semibold)
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
        }
        .padding(24)
    }

    private func confirmation(_ email: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "envelope.badge.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.brand)
                .padding(.top, 60)
            Text("Check your inbox").font(.title.bold())
            Text("We sent a confirmation link to **\(email)**. Open it on this iPhone and you'll be signed in automatically.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Go to Sign In", action: onSignIn)
                .buttonStyle(.primary)
                .padding(.top, 12)
        }
        .padding(24)
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .foregroundStyle(configuration.isOn ? Theme.brand : .secondary)
                configuration.label
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityValue(configuration.isOn ? "checked" : "unchecked")
    }
}
