public import Domain
public import LedgerUI
public import SwiftUI
import DesignSystem
import FlowCore
import Routing

/// Screen 6 — every transaction, searchable, filterable, grouped by day.
public struct TransactionsView: View {
    @State private var model: TransactionsViewModel
    @Environment(Router.self) private var router
    @Environment(\.currency) private var currency
    let title: String

    public init(context: LedgerContext, filter: TransactionFilter = .all, accountID: UUID? = nil, title: String = "Transactions") {
        _model = State(initialValue: TransactionsViewModel(context: context, filter: filter, accountID: accountID))
        self.title = title
    }

    public var body: some View {
        List {
            Section {
                PillPicker(TransactionFilter.allCases, selection: $model.filter) { $0.title }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
            }
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.transactions) { transaction in
                        NavigationLink(value: Route.transaction(transaction.id)) {
                            TransactionRow(transaction, subtitle: subtitle(for: transaction))
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await model.delete(transaction) }
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                router.present(.transactionEditor(kind: transaction.kind, editing: transaction.id))
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(Theme.brand)
                        }
                    }
                } header: {
                    HStack {
                        Text(DayTitle.title(for: section.day, now: model.context.now(), calendar: model.context.calendar))
                        Spacer()
                        AmountText(section.net, style: .signed).font(.caption.weight(.semibold))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if model.isEmpty {
                if model.query.isEmpty {
                    ContentUnavailableView {
                        Label("No transactions", systemImage: "list.bullet.rectangle")
                    } description: {
                        Text("Transactions you add will appear here.")
                    } actions: {
                        Button("Add Expense") { router.present(.transactionEditor(kind: .expense)) }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    ContentUnavailableView.search(text: model.query)
                }
            } else if !model.isLoaded {
                LoadingView()
            }
        }
        .navigationTitle(title)
        .searchable(text: $model.query, prompt: "Search transactions")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                NavigationLink(value: Route.calendar) {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("Calendar")
                Menu {
                    Button("Add Expense", systemImage: "minus.circle") { router.present(.transactionEditor(kind: .expense)) }
                    Button("Add Income", systemImage: "plus.circle") { router.present(.transactionEditor(kind: .income)) }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add transaction")
                .accessibilityIdentifier("transactions.add")
            }
        }
        .refreshable { await model.refresh() }
        .task { await model.observe() }
        // Debounce typing: recompute 150 ms after the last keystroke, cancelling stale work.
        .task(id: model.query) {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            model.applyQuery()
        }
        .onChange(of: model.filter) { model.applyQuery() }
        .errorAlert($model.errorMessage)
    }

    private func subtitle(for transaction: LedgerTransaction) -> String {
        let time = transaction.date.formatted(date: .omitted, time: .shortened)
        return "\(transaction.category.name) · \(time)"
    }
}
