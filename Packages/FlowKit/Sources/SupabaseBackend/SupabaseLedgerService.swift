public import Foundation
public import LedgerData
import Auth
import Domain
import FlowCore
import PostgREST

/// `RemoteLedgerService` over PostgREST: bulk upserts on push, paged "changed since" queries on pull.
public final class SupabaseLedgerService: RemoteLedgerService {
    static let pageSize = 1000
    static let pushChunk = 500

    private let client: PostgrestClient

    public init(configuration: SupabaseConfiguration, auth: SupabaseAuthService) {
        let key = configuration.publishableKey
        client = PostgrestClient(configuration: PostgrestClient.Configuration(
            url: configuration.url.appending(path: "rest/v1"),
            schema: SupabaseConfiguration.schema,
            headers: ["apikey": key],
            logger: nil,
            fetch: { request in
                // Attach the *user's* JWT (refreshed if needed) so Row Level Security sees `auth.uid()`.
                var request = request
                let token = try await auth.accessToken()
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                return try await URLSession.shared.data(for: request)
            }
        ))
    }

    // MARK: Push

    public func push(_ changes: ChangeSet) async throws(SyncError) {
        do {
            // Parents before children so foreign keys (transaction → account, contribution → goal) resolve.
            try await upsert(changes.profiles.map(ProfileRow.init), into: .profile)
            try await upsert(changes.accounts.map(AccountRow.init), into: .account)
            try await upsert(changes.goals.map(GoalRow.init), into: .goal)
            try await upsert(changes.recurringRules.map(RecurringRuleRow.init), into: .recurringRule)
            try await upsert(changes.budgets.map(BudgetRow.init), into: .budget)
            try await upsert(changes.transactions.map(TransactionRow.init), into: .transaction)
            try await upsert(changes.contributions.map(ContributionRow.init), into: .goalContribution)
        } catch {
            throw Self.map(error)
        }
    }

    private func upsert(_ rows: [some Encodable & Sendable], into kind: RecordKind) async throws {
        for start in stride(from: 0, to: rows.count, by: Self.pushChunk) {
            let chunk = Array(rows[start ..< min(start + Self.pushChunk, rows.count)])
            try await client.from(kind.rawValue).upsert(chunk, onConflict: "id", returning: .minimal).execute()
        }
    }

    // MARK: Pull

    public func pull(since: Date?) async throws(SyncError) -> ChangeSet {
        do {
            // The seven tables are independent reads — fetch them concurrently (one round-trip of latency).
            async let profiles: [ProfileRow] = fetch(.profile, since: since)
            async let accounts: [AccountRow] = fetch(.account, since: since)
            async let transactions: [TransactionRow] = fetch(.transaction, since: since)
            async let budgets: [BudgetRow] = fetch(.budget, since: since)
            async let goals: [GoalRow] = fetch(.goal, since: since)
            async let contributions: [ContributionRow] = fetch(.goalContribution, since: since)
            async let rules: [RecurringRuleRow] = fetch(.recurringRule, since: since)
            return try await ChangeSet(
                profiles: profiles.map(\.model),
                accounts: accounts.map(\.model),
                transactions: transactions.map(\.model),
                budgets: budgets.map(\.model),
                goals: goals.map(\.model),
                contributions: contributions.map(\.model),
                recurringRules: rules.map(\.model)
            )
        } catch {
            throw Self.map(error)
        }
    }

    private func fetch<Row: Decodable & Sendable>(_ kind: RecordKind, since: Date?) async throws -> [Row] {
        var rows: [Row] = []
        var offset = 0
        while true {
            var query = client.from(kind.rawValue).select()
            if let since {
                query = query.gt("updated_at", value: since)
            }
            let page: [Row] = try await query
                .order("updated_at")
                .order("id")
                .range(from: offset, to: offset + Self.pageSize - 1)
                .execute()
                .value
            rows += page
            guard page.count == Self.pageSize else { return rows }
            offset += Self.pageSize
        }
    }

    // MARK: Errors

    static func map(_ error: any Error) -> SyncError {
        if let error = error as? SyncError {
            return error
        }
        if let urlError = error as? URLError, urlError.isConnectivityProblem {
            return .offline
        }
        if let authError = error as? Auth.AuthError {
            if case .sessionMissing = authError {
                return .unauthorized
            }
            if case let .api(_, _, _, response) = authError, response.statusCode == 400 || response.statusCode == 401 {
                return .unauthorized
            }
            return .server(authError.message)
        }
        if let error = error as? PostgrestError {
            // PGRST301/303: JWT invalid or expired.
            if error.code == "PGRST301" || error.code == "PGRST303" {
                return .unauthorized
            }
            return .server(error.message)
        }
        if let error = error as? HTTPError, error.response.statusCode == 401 {
            return .unauthorized
        }
        return .server("Couldn't reach the server. Your changes are saved and will sync later.")
    }
}
