public import LedgerUI
public import SwiftUI
import DesignSystem
import Domain
import FlowCore

/// Screen 28 — appearance, currency, notifications, data & sync, privacy, about.
public struct SettingsView: View {
    @State private var model: ProfileModel
    @State private var confirmsDelete = false
    @State private var deleteConfirmation = ""
    @State private var notificationsDenied = false
    @Environment(AppPreferences.self) private var preferences

    public init(context: LedgerContext, services: AccountServices) {
        _model = State(initialValue: ProfileModel(context: context, services: services))
    }

    public var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $preferences.appearance) {
                    ForEach(AppearancePreference.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Hide balances", isOn: $preferences.hideAmounts)
            }

            Section {
                Picker("Currency", selection: Binding(
                    get: { model.profile?.currencyCode ?? "USD" },
                    set: { code in Task { await model.setCurrency(code) } }
                )) {
                    ForEach(CurrencyFormat.supportedCodes, id: \.self) { code in
                        Text("\(code) · \(Locale.current.localizedString(forCurrencyCode: code) ?? code)").tag(code)
                    }
                }
            } header: {
                Text("Currency")
            } footer: {
                Text("Changes how amounts are shown. Existing amounts are not converted.")
            }

            Section {
                Toggle("Bill & weekly reminders", isOn: Binding(
                    get: { preferences.remindersEnabled },
                    set: { enabled in Task { await setReminders(enabled) } }
                ))
                .accessibilityIdentifier("settings.reminders")
            } header: {
                Text("Notifications")
            } footer: {
                Text(notificationsDenied
                    ? "Notifications are turned off for FlowMoney in iOS Settings."
                    : "A reminder the day before each subscription renews, and a Monday summary of last week.")
            }

            Section("Data & Sync") {
                LabeledContent(
                    "Storage",
                    value: model.services.isDemo ? "This iPhone only (demo)" : "Supabase · \(model.services.backendHost ?? "")"
                )
                if !model.services.isDemo {
                    LabeledContent("Status", value: statusText)
                    if let last = model.syncStatus.lastSyncedAt {
                        LabeledContent("Last synced") {
                            Text(last, format: .relative(presentation: .named))
                        }
                    }
                    Button("Sync Now") { Task { await model.syncNow() } }
                        .disabled(model.syncStatus.phase == .syncing)
                }
            }

            Section("Privacy") {
                Link("Privacy Policy", destination: URL(string: "https://flowmoney.app/privacy") ?? URL(filePath: "/"))
                Link("Terms of Service", destination: URL(string: "https://flowmoney.app/terms") ?? URL(filePath: "/"))
                if !model.services.isDemo {
                    Button("Delete Account", role: .destructive) { confirmsDelete = true }
                        .accessibilityIdentifier("settings.deleteAccount")
                }
            }

            Section("About") {
                LabeledContent("Version", value: Self.version)
            }
        }
        .navigationTitle("Settings")
        .alert("Delete your account?", isPresented: $confirmsDelete) {
            TextField("Type DELETE to confirm", text: $deleteConfirmation)
            Button("Delete Forever", role: .destructive) {
                guard deleteConfirmation == "DELETE" else { return }
                Task { await model.deleteAccount() }
            }
            Button("Cancel", role: .cancel) { deleteConfirmation = "" }
        } message: {
            Text("This permanently deletes your account and all your data from our servers. This can't be undone.")
        }
        .overlay {
            if model.isWorking {
                ProgressView().controlSize(.large).frame(maxWidth: .infinity, maxHeight: .infinity).background(.ultraThinMaterial)
            }
        }
        .task { await model.observe() }
        .task { await model.observeSyncStatus() }
        .errorAlert($model.errorMessage)
    }

    private var statusText: String {
        switch model.syncStatus.phase {
        case .localOnly: "Local only"
        case .idle: model.syncStatus.pendingChanges == 0 ? "Up to date" : "\(model.syncStatus.pendingChanges) changes waiting"
        case .syncing: "Syncing…"
        case .offline: "Offline — changes saved on this iPhone"
        case let .failed(message): message
        }
    }

    /// Asks for permission only when the user turns the toggle on (never at launch).
    private func setReminders(_ enabled: Bool) async {
        guard enabled else {
            preferences.remindersEnabled = false
            await model.services.reminders.replaceAll(with: [])
            return
        }
        let granted = await model.services.reminders.requestAuthorization()
        notificationsDenied = !granted
        preferences.remindersEnabled = granted
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}

/// Screen 29 — app lock with Face ID / Touch ID.
public struct SecurityView: View {
    let services: AccountServices
    @State private var failed = false
    @Environment(AppPreferences.self) private var preferences

    public init(services: AccountServices) {
        self.services = services
    }

    public var body: some View {
        let biometry = services.authenticator.availableBiometry()
        Form {
            Section {
                VStack(spacing: 12) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.brand)
                    Text("Secure your app").font(.title3.bold())
                    Text("Use \(biometry.title) to unlock FlowMoney and keep your finances private.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section {
                Toggle("Require \(biometry.title)", isOn: Binding(
                    get: { preferences.appLockEnabled },
                    set: { enabled in Task { await setLock(enabled, biometry: biometry) } }
                ))
                .accessibilityIdentifier("security.appLock")
            } footer: {
                Text(failed
                    ? "Couldn't verify it's you, so App Lock wasn't turned on."
                    : "FlowMoney locks when you leave the app and hides its contents in the app switcher.")
            }
        }
        .navigationTitle("Security")
    }

    /// Turning the lock on requires authenticating once, so nobody can lock the owner out.
    private func setLock(_ enabled: Bool, biometry _: BiometryKind) async {
        guard enabled else {
            preferences.appLockEnabled = false
            return
        }
        let ok = await services.authenticator.authenticate(reason: "Turn on App Lock")
        failed = !ok
        preferences.appLockEnabled = ok
    }
}
