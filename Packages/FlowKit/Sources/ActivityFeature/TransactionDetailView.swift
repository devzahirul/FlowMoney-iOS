public import Foundation
public import LedgerUI
public import SwiftUI
import DesignSystem
import Domain
import FlowCore
import Observation
import Routing

@MainActor
@Observable
final class TransactionDetailModel: LedgerObserving {
    private(set) var transaction: LedgerTransaction?
    private(set) var accountName = ""
    private(set) var ruleName: String?
    private(set) var isMissing = false
    var errorMessage: String?

    let context: LedgerContext
    var lastRevision: Int?
    let id: UUID

    init(context: LedgerContext, id: UUID) {
        self.context = context
        self.id = id
    }

    func update(with snapshot: LedgerSnapshot) {
        transaction = snapshot.transactions.first { $0.id == id }
        isMissing = transaction == nil
        accountName = transaction.flatMap { snapshot.accountsByID[$0.accountID]?.name } ?? ""
        ruleName = transaction?.recurringRuleID.flatMap { ruleID in snapshot.recurringRules.first { $0.id == ruleID }?.name }
    }

    func delete() async -> Bool {
        do {
            try await context.repository.perform(.deleteTransaction(id: id))
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

/// Screen 7 — one transaction.
public struct TransactionDetailView: View {
    @State private var model: TransactionDetailModel
    @State private var confirmsDelete = false
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    public init(context: LedgerContext, id: UUID) {
        _model = State(initialValue: TransactionDetailModel(context: context, id: id))
    }

    public var body: some View {
        Group {
            if let transaction = model.transaction {
                content(transaction)
            } else if model.isMissing {
                ContentUnavailableView("Transaction deleted", systemImage: "trash", description: Text("This transaction no longer exists."))
            } else {
                LoadingView()
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.observe() }
        .errorAlert($model.errorMessage)
    }

    private func content(_ transaction: LedgerTransaction) -> some View {
        ScreenScroll {
            VStack(spacing: 10) {
                IconBadge(transaction.category.symbol, color: transaction.category.color, size: 72)
                Text(transaction.displayTitle).font(.title2.bold()).multilineTextAlignment(.center)
                Text(transaction.category.name).foregroundStyle(.secondary)
                AmountText(transaction.signedAmount, style: .signed)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text(transaction.date.formatted(date: .complete, time: .shortened))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)

            VStack(spacing: 0) {
                detailRow("Type", transaction.kind == .expense ? "Expense" : "Income", symbol: "arrow.left.arrow.right")
                Divider()
                detailRow("Account", model.accountName, symbol: "building.columns")
                Divider()
                detailRow("Category", transaction.category.name, symbol: transaction.category.symbol)
                if let ruleName = model.ruleName {
                    Divider()
                    detailRow("Repeats", ruleName, symbol: "repeat")
                }
                if !transaction.note.isEmpty {
                    Divider()
                    detailRow("Note", transaction.note, symbol: "note.text")
                }
            }
            .card(padding: 0)

            VStack(spacing: 12) {
                Button("Edit Transaction") {
                    router.present(.transactionEditor(kind: transaction.kind, editing: transaction.id))
                }
                .buttonStyle(.secondary)
                .accessibilityIdentifier("detail.edit")
                Button("Delete", role: .destructive) { confirmsDelete = true }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("detail.delete")
            }
            .confirmationDialog("Delete this transaction?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task {
                        if await model.delete() {
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private func detailRow(_ title: String, _ value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.brand).frame(width: 24)
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}
