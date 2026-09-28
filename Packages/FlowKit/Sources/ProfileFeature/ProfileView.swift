public import LedgerUI
public import SwiftUI
import DesignSystem
import Domain
import Routing

/// Screen 27 — the signed-in user, their stats, and account actions.
public struct ProfileView: View {
    @State private var model: ProfileModel
    @State private var confirmsSignOut = false
    @Environment(Router.self) private var router

    public init(context: LedgerContext, services: AccountServices) {
        _model = State(initialValue: ProfileModel(context: context, services: services))
    }

    public var body: some View {
        List {
            Section {
                VStack(spacing: 10) {
                    Text(model.profile?.initials ?? "")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.onBrand)
                        .frame(width: 88, height: 88)
                        .background(Theme.heroGradient, in: .circle)
                    Text(model.profile?.displayName.isEmpty == false ? model.profile?.displayName ?? "" : "Your name")
                        .font(.title2.bold())
                    Text(model.services.isDemo ? "Demo mode · data stays on this iPhone" : model.services.email)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 0) {
                        stat("\(model.goalCount)", "Goals")
                        Divider().frame(height: 32)
                        stat("\(model.accountCount)", "Accounts")
                        Divider().frame(height: 32)
                        stat("\(model.transactionCount)", "Transactions")
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                Button {
                    router.present(.editProfile)
                } label: {
                    row("Personal information", "person.fill", Theme.palette[2])
                }
                NavigationLink(value: Route.accounts) { row("Accounts", "building.columns.fill", Theme.palette[4]) }
                NavigationLink(value: Route.recurring) { row("Recurring & bills", "repeat", Theme.palette[1]) }
                NavigationLink(value: Route.search) { row("Search", "magnifyingglass", Theme.palette[6]) }
            }

            Section {
                NavigationLink(value: Route.settings) { row("Settings", "gearshape.fill", Theme.neutral) }
                    .accessibilityIdentifier("profile.settings")
                NavigationLink(value: Route.security) { row("Security", "lock.fill", Theme.palette[8]) }
                NavigationLink(value: Route.export) { row("Export report", "square.and.arrow.up.fill", Theme.palette[0]) }
                Link(destination: URL(string: "mailto:support@flowmoney.app?subject=FlowMoney%20support") ?? URL(filePath: "/")) {
                    row("Help & support", "questionmark.circle.fill", Theme.palette[7])
                }
            }

            Section {
                Button(role: .destructive) {
                    confirmsSignOut = true
                } label: {
                    HStack {
                        Spacer()
                        if model.isWorking {
                            ProgressView()
                        } else {
                            Text(model.services.isDemo ? "Exit Demo" : "Log Out")
                        }
                        Spacer()
                    }
                }
                .accessibilityIdentifier("profile.signOut")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Profile")
        .confirmationDialog(
            model.services.isDemo ? "Exit the demo? Demo data is removed." : "Log out of FlowMoney?",
            isPresented: $confirmsSignOut,
            titleVisibility: .visible
        ) {
            Button(model.services.isDemo ? "Exit Demo" : "Log Out", role: .destructive) {
                Task { await model.signOut() }
            }
            .accessibilityIdentifier("profile.confirmSignOut")
        } message: {
            if !model.services.isDemo, model.syncStatus.pendingChanges > 0 {
                Text("\(model.syncStatus.pendingChanges) changes haven't synced yet and will be lost.")
            }
        }
        .task { await model.observe() }
        .task { await model.observeSyncStatus() }
        .errorAlert($model.errorMessage)
    }

    private func stat(_ value: String, _ title: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.headline)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func row(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label {
            Text(title).foregroundStyle(.primary)
        } icon: {
            IconBadge(symbol, color: color, size: 30)
        }
    }
}

/// Edit display name.
public struct EditProfileView: View {
    @State private var model: ProfileModel
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    public init(context: LedgerContext, services: AccountServices) {
        _model = State(initialValue: ProfileModel(context: context, services: services))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                        .accessibilityIdentifier("profile.name")
                }
                if !model.services.isDemo {
                    Section("Email") {
                        Text(model.services.email).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Personal Information")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task {
                        if await model.rename(name) {
                            dismiss()
                        }
                    } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                await model.observe()
            }
            .onChange(of: model.profile?.displayName, initial: true) { _, newName in
                if name.isEmpty {
                    name = newName ?? ""
                }
            }
            .errorAlert($model.errorMessage)
        }
        .presentationDetents([.medium])
    }
}
