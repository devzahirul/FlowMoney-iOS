public import Domain
public import SwiftUI
import DesignSystem

/// Screen 1 — first launch. Routes to sign-up, sign-in or the offline demo.
public struct OnboardingView: View {
    private enum Destination: Hashable { case login, signUp }

    let auth: any AuthService
    let actions: AuthActions
    @State private var path: [Destination] = []
    @State private var isStartingDemo = false

    public init(auth: any AuthService, actions: AuthActions) {
        self.auth = auth
        self.actions = actions
    }

    public var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 28) {
                Spacer(minLength: 12)
                hero
                VStack(alignment: .leading, spacing: 14) {
                    feature("chart.bar.fill", "Track your spending")
                    feature("target", "Plan for your goals")
                    feature("leaf.fill", "Build a brighter future")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                Spacer(minLength: 12)
                buttons
            }
            .padding(24)
            .background(Theme.background)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .login: LoginView(model: LoginModel(auth: auth, actions: actions), onSignUp: { path = [.signUp] })
                case .signUp: SignUpView(model: SignUpModel(auth: auth, actions: actions), onSignIn: { path = [.login] })
                }
            }
        }
        .tint(Theme.brand)
    }

    private var hero: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.brandSoft).frame(width: 220, height: 220)
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 70))
                    .foregroundStyle(Theme.brand.gradient)
                    .offset(x: -30, y: -20)
                Image(systemName: "dollarsign.circle.fill")
                    .font(.system(size: 54))
                    .foregroundStyle(Theme.palette[5].gradient)
                    .offset(x: 50, y: 35)
                Image(systemName: "leaf.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.income)
                    .offset(x: 55, y: -55)
            }
            .accessibilityHidden(true)
            Wordmark()
            Text("A simpler way to manage your money")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var buttons: some View {
        VStack(spacing: 12) {
            if auth.isConfigured {
                Button("Get Started") { path = [.signUp] }
                    .buttonStyle(.primary)
                    .accessibilityIdentifier("onboarding.getStarted")
                Button("I already have an account") { path = [.login] }
                    .buttonStyle(.secondary)
                    .accessibilityIdentifier("onboarding.signIn")
            }
            Button {
                isStartingDemo = true
                Task {
                    await actions.startDemo()
                    isStartingDemo = false
                }
            } label: {
                if isStartingDemo {
                    ProgressView()
                } else {
                    Text(auth.isConfigured ? "Explore the demo" : "Start with demo data")
                }
            }
            .buttonStyle(auth.isConfigured ? AnyButtonStyle(.plainBrand) : AnyButtonStyle(.primary))
            .disabled(isStartingDemo)
            .accessibilityIdentifier("onboarding.demo")
        }
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        Label {
            Text(title).font(.body.weight(.medium))
        } icon: {
            IconBadge(symbol, color: Theme.brand, size: 34)
        }
    }
}

/// Type-erased button style so the demo button can switch style with configuration.
struct AnyButtonStyle: ButtonStyle {
    private let make: @MainActor (Configuration) -> AnyView

    init(_ style: some ButtonStyle) {
        make = { AnyView(style.makeBody(configuration: $0)) }
    }

    func makeBody(configuration: Configuration) -> some View {
        make(configuration)
    }
}

struct PlainBrandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.brand)
            .frame(maxWidth: .infinity, minHeight: 44)
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

extension ButtonStyle where Self == PlainBrandButtonStyle {
    static var plainBrand: PlainBrandButtonStyle {
        PlainBrandButtonStyle()
    }
}
