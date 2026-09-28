# Architecture

## Modules

| Module | Responsibility | Depends on |
|---|---|---|
| `FlowCore` | `Money` (exact minor units), `CurrencyFormat`, `YearMonth`, deterministic UUIDs, logging/signposts | — |
| `Domain` | Entities, `LedgerRepository` / `AuthService` contracts, **every business rule** (pure functions), demo data | FlowCore |
| `LedgerData` | Offline-first `LocalLedgerRepository` actor: state, persistence, outbox, sync, mutation rules | Domain |
| `SupabaseBackend` | `AuthService` + `RemoteLedgerService` over supabase-swift; row DTOs; error mapping | LedgerData, supabase-swift |
| `DesignSystem` | Tokens (light/dark), components (cards, progress, pills, keypad), SF Symbol mapping | Domain |
| `Routing` | `Route` / `SheetRoute` enums, `Router` (tabs, stacks, sheets, deep links) | Domain |
| `LedgerUI` | `LedgerContext` (DI), `LedgerObserving` base, shared rows, `AmountText`, preferences | DesignSystem, Routing |
| `*Feature` (7) | Screens + view models: Auth, Home, Activity, Accounts, Plan, Insights, Profile | LedgerUI, Routing |
| `AppFeature` | Composition root: `AppEnvironment` (live / UI-test wiring), `AppModel` session state machine, tabs, route resolver | everything |
| `TestSupport` | Fixtures, fixed UTC calendar, fake remote/auth/reminders | Domain, LedgerData |

Rules enforced by the module graph (the compiler, not code review):
- Features cannot import each other or `LedgerData`/`SupabaseBackend`.
- `Domain` cannot import SwiftUI or any I/O.
- Only `SupabaseBackend` can see the Supabase SDK.

## Data flow

```
View ──intent──▶ ViewModel ──LedgerMutation──▶ LocalLedgerRepository (actor)
  ▲                                               │ validate · stamp · outbox · persist
  └──── @Observable state ◀── derive ◀── LedgerSnapshot stream ◀┘
                                                  │
                                    debounced sync ▼
                               RemoteLedgerService (Supabase)
```

1. A view calls a view-model method (`save()`).
2. The view model sends a `LedgerMutation` (one enum for every write → atomic batches, easy to log and test).
3. The repository actor applies it via `LedgerMutator` (pure), writes to disk, records the outbox, publishes a new
   immutable snapshot, and schedules a debounced sync.
4. Every subscribed view model receives the snapshot, recomputes its derived state with `Domain` functions (only if the
   revision changed), and SwiftUI re-renders exactly the properties that changed.

## Concurrency model

- UI and view models: `@MainActor`.
- Ledger state: one `actor` — serialised read-modify-write without locks. Its initializer is `async` so the disk read
  never runs on the main actor at launch.
- Sync handles actor re-entrancy explicitly (outbox revisions), see ADR-0002.
- All cross-actor types are `Sendable`; Swift 6 language mode with complete checking. The only `@unchecked Sendable` is
  `InMemoryLedgerPersistence` (NSLock-guarded; used by tests and UI-test runs).
- Tasks are tied to view lifetime with `.task {}` (auto-cancel); typing in search is debounced with `.task(id:)`.

## Dependency injection

Constructor injection only. `AppEnvironment` is the single place where real services are created (`.live()`) or replaced
(`-uiTesting` → in-memory storage, demo data, clean defaults). Tests build a real repository with in-memory persistence
in one line, so view-model tests exercise the same store the app uses.

## Performance notes

- Snapshot indexes (balances, goal totals, accounts by ID) are built once per change on the actor.
- Date-range queries binary-search the date-sorted transaction array (`partitioningIndex`).
- Net-worth history walks transactions once backwards ("un-applying") — O(n + months), not O(n × months).
- Currency formatters are built once per currency change and shared through the environment.
- PDF rendering runs in a detached task; search is debounced 120–150 ms.
- Signposts (`Log.signposter`) mark `app.restoreSession`, `ledger.load`, `ledger.snapshot`, `ledger.sync` for Instruments.
