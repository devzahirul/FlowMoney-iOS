public import Foundation
public import LedgerUI
public import SwiftUI
import Charts
import DesignSystem
import Domain
import FlowCore
import Observation
import Routing

@MainActor
@Observable
final class AccountDetailModel: LedgerObserving {
    private(set) var account: Account?
    private(set) var balance = Money.zero
    private(set) var sections: [DaySection] = []
    private(set) var monthIn = Money.zero
    private(set) var monthOut = Money.zero
    private(set) var isMissing = false

    let context: LedgerContext
    var lastRevision: Int?
    let id: UUID

    init(context: LedgerContext, id: UUID) {
        self.context = context
        self.id = id
    }

    func update(with snapshot: LedgerSnapshot) {
        account = snapshot.accountsByID[id]
        isMissing = account == nil
        balance = snapshot.balance(of: id)
        let transactions = snapshot.transactions.filter { $0.accountID == id }
        sections = TransactionQuery.groupedByDay(transactions.prefix(200), calendar: context.calendar)
        let month = context.currentMonth.interval(in: context.calendar)
        let thisMonth = transactions.filter { month.contains($0.date) }
        monthIn = thisMonth.filter { $0.kind == .income }.sum(\.amount)
        monthOut = thisMonth.filter { $0.kind == .expense }.sum(\.amount)
    }
}

public struct AccountDetailView: View {
    @State private var model: AccountDetailModel
    @Environment(Router.self) private var router

    public init(context: LedgerContext, id: UUID) {
        _model = State(initialValue: AccountDetailModel(context: context, id: id))
    }

    public var body: some View {
        Group {
            if let account = model.account {
                content(account)
            } else if model.isMissing {
                ContentUnavailableView("Account deleted", systemImage: "trash")
            } else {
                LoadingView()
            }
        }
        .background(Theme.background)
        .navigationTitle(model.account?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { router.present(.accountEditor(editing: model.id)) }
            }
        }
        .task { await model.observe() }
    }

    private func content(_ account: Account) -> some View {
        List {
            Section {
                VStack(spacing: 10) {
                    IconBadge(account.kind.symbol, color: account.kind.color, size: 56)
                    AmountText(model.balance).font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text([account.institution, account.kind.title].filter { !$0.isEmpty }.joined(separator: " · "))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 24) {
                        stat("In this month", model.monthIn, Theme.income)
                        stat("Out this month", model.monthOut, Theme.expense)
                    }
                    .padding(.top, 4)
                    Button {
                        router.present(.transactionEditor(kind: .expense, accountID: account.id))
                    } label: {
                        Label("Add Transaction", systemImage: "plus")
                    }
                    .buttonStyle(.secondary)
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            ForEach(model.sections) { section in
                Section(DayTitle.title(for: section.day, now: model.context.now(), calendar: model.context.calendar)) {
                    ForEach(section.transactions) { transaction in
                        NavigationLink(value: Route.transaction(transaction.id)) {
                            TransactionRow(transaction)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
    }

    private func stat(_ title: String, _ amount: Money, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            AmountText(amount).font(.subheadline.weight(.semibold)).foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }
}
