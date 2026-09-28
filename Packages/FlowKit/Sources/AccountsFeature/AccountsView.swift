public import LedgerUI
public import SwiftUI
import DesignSystem
import Domain
import FlowCore
import Observation
import Routing

@MainActor
@Observable
final class AccountsModel: LedgerObserving {
    struct Row: Identifiable, Equatable {
        let account: Account
        let balance: Money
        var id: UUID {
            account.id
        }
    }

    private(set) var rows: [Row] = []
    private(set) var total = Money.zero
    private(set) var monthChange: Double?
    private(set) var isLoaded = false
    var errorMessage: String?

    let context: LedgerContext
    var lastRevision: Int?

    init(context: LedgerContext) {
        self.context = context
    }

    func update(with snapshot: LedgerSnapshot) {
        rows = snapshot.accounts.map { Row(account: $0, balance: snapshot.balance(of: $0.id)) }
        let netWorth = NetWorth.summary(for: snapshot, months: 2, now: context.now(), calendar: context.calendar)
        total = netWorth.total
        let previous = netWorth.history.first?.amount ?? .zero
        monthChange = previous.isZero ? nil : netWorth.monthChange.fraction(of: previous.magnitude)
        isLoaded = true
    }

    func delete(_ account: Account) async {
        do {
            try await context.repository.perform(.deleteAccount(id: account.id))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// Screen 5 — every account with its balance.
public struct AccountsView: View {
    @State private var model: AccountsModel
    @State private var pendingDelete: Account?
    @Environment(Router.self) private var router

    public init(context: LedgerContext) {
        _model = State(initialValue: AccountsModel(context: context))
    }

    public var body: some View {
        ScreenScroll {
            VStack(alignment: .leading, spacing: 8) {
                Text("Total balance").font(.subheadline.weight(.medium)).opacity(0.85)
                AmountText(model.total)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                if let change = model.monthChange {
                    Text("\(change >= 0 ? "+" : "")\(change.formatted(.percent.precision(.fractionLength(1)))) this month")
                        .font(.footnote.weight(.semibold))
                        .opacity(0.9)
                }
            }
            .foregroundStyle(.white)
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.heroGradient, in: .rect(cornerRadius: 24))
            .accessibilityElement(children: .combine)

            VStack(spacing: 0) {
                ForEach(model.rows) { row in
                    NavigationLink(value: Route.account(row.id)) {
                        AccountRow(account: row.account, balance: row.balance)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Edit", systemImage: "pencil") { router.present(.accountEditor(editing: row.id)) }
                        Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = row.account }
                    }
                    if row.id != model.rows.last?.id {
                        Divider().padding(.leading, 68)
                    }
                }
            }
            .card(padding: 0)

            Button {
                router.present(.accountEditor())
            } label: {
                Label("Add Account", systemImage: "plus")
            }
            .buttonStyle(.secondary)
            .accessibilityIdentifier("accounts.add")
        }
        .navigationTitle("Accounts")
        .task { await model.observe() }
        .errorAlert($model.errorMessage)
        .confirmationDialog(
            "Delete \(pendingDelete?.name ?? "account")?",
            isPresented: Binding(get: { pendingDelete != nil }, set: {
                if !$0 {
                    pendingDelete = nil
                }
            }),
            titleVisibility: .visible
        ) {
            Button("Delete Account and Its Transactions", role: .destructive) {
                if let account = pendingDelete {
                    Task { await model.delete(account) }
                }
            }
        } message: {
            Text("This removes the account and all of its transactions on every device.")
        }
    }
}

struct AccountRow: View {
    let account: Account
    let balance: Money

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(account.kind.symbol, color: account.kind.color, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.name).font(.body.weight(.medium))
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            AmountText(balance)
                .font(.body.weight(.semibold))
                .foregroundStyle(balance.isNegative ? Theme.expense : .primary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(16)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        [account.kind.title, account.lastFour.map { "•••• \($0)" }].compactMap(\.self).joined(separator: " · ")
    }
}
