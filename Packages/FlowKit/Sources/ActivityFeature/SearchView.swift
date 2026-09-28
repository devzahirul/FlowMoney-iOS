public import LedgerUI
public import SwiftUI
import DesignSystem
import Domain
import FlowCore
import Observation
import Routing

@MainActor
@Observable
final class SearchModel: LedgerObserving {
    enum Scope: String, CaseIterable, Identifiable {
        case all = "All", transactions = "Transactions", accounts = "Accounts", goals = "Goals"
        var id: Self {
            self
        }
    }

    var query = ""
    var scope = Scope.all
    private(set) var transactions: [LedgerTransaction] = []
    private(set) var accounts: [Account] = []
    private(set) var goals: [Goal] = []
    private(set) var totalMatches = 0

    let context: LedgerContext
    var lastRevision: Int?
    private var snapshot: LedgerSnapshot?

    init(context: LedgerContext) {
        self.context = context
    }

    func update(with snapshot: LedgerSnapshot) {
        self.snapshot = snapshot
        run()
    }

    func run() {
        guard let snapshot else { return }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            (transactions, accounts, goals, totalMatches) = ([], [], [], 0)
            return
        }
        let allTransactions = TransactionQuery.search(text, in: snapshot)
        totalMatches = allTransactions.count
        transactions = Array(allTransactions.prefix(scope == .transactions ? 200 : 20))
        accounts = snapshot.accounts
            .filter { $0.name.localizedCaseInsensitiveContains(text) || $0.institution.localizedCaseInsensitiveContains(text) }
        goals = snapshot.goals.filter { $0.name.localizedCaseInsensitiveContains(text) }
    }

    var hasResults: Bool {
        !transactions.isEmpty || !accounts.isEmpty || !goals.isEmpty
    }
}

/// Screen 23 — search across transactions, accounts and goals, with recent searches.
public struct SearchView: View {
    @State private var model: SearchModel
    @Environment(AppPreferences.self) private var preferences

    public init(context: LedgerContext) {
        _model = State(initialValue: SearchModel(context: context))
    }

    public var body: some View {
        List {
            if model.query.isEmpty {
                idleContent
            } else {
                Section {
                    Picker("Scope", selection: $model.scope) {
                        ForEach(SearchModel.Scope.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                results
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .overlay {
            if !model.query.isEmpty, !model.hasResults {
                ContentUnavailableView.search(text: model.query)
            }
        }
        .navigationTitle("Search")
        .searchable(text: $model.query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search coffee, Uber, rent…")
        .onSubmit(of: .search) { preferences.addRecentSearch(model.query) }
        .task { await model.observe() }
        .task(id: model.query) {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            model.run()
        }
        .onChange(of: model.scope) { model.run() }
    }

    @ViewBuilder
    private var idleContent: some View {
        if !preferences.recentSearches.isEmpty {
            Section {
                ForEach(preferences.recentSearches, id: \.self) { recent in
                    Button {
                        model.query = recent
                    } label: {
                        Label(recent, systemImage: "clock.arrow.circlepath").foregroundStyle(.primary)
                    }
                }
            } header: {
                HStack {
                    Text("Recent")
                    Spacer()
                    Button("Clear") { preferences.clearRecentSearches() }.font(.caption)
                }
            }
        }
        Section("Suggestions") {
            ForEach([CategoryID.food, .transport, .shopping, .subscriptions], id: \.self) { id in
                Button {
                    model.query = id.category.name
                } label: {
                    Label(id.category.name, systemImage: id.category.symbol).foregroundStyle(.primary)
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if model.scope == .all || model.scope == .transactions, !model.transactions.isEmpty {
            Section("Transactions (\(model.totalMatches))") {
                ForEach(model.transactions) { transaction in
                    NavigationLink(value: Route.transaction(transaction.id)) {
                        TransactionRow(transaction, subtitle: transaction.date.formatted(date: .abbreviated, time: .omitted))
                    }
                }
            }
        }
        if model.scope == .all || model.scope == .accounts, !model.accounts.isEmpty {
            Section("Accounts") {
                ForEach(model.accounts) { account in
                    NavigationLink(value: Route.account(account.id)) {
                        Label(account.name, systemImage: account.kind.symbol)
                    }
                }
            }
        }
        if model.scope == .all || model.scope == .goals, !model.goals.isEmpty {
            Section("Goals") {
                ForEach(model.goals) { goal in
                    NavigationLink(value: Route.goal(goal.id)) {
                        Label(goal.name, systemImage: goal.symbol.symbol)
                    }
                }
            }
        }
    }
}
