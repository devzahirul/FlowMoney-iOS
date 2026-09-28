# ADR-0005: Supabase via the official SDK, isolated in one module

**Status:** Accepted · 2026-09-28

## Decision
Use `supabase-swift` (Auth + PostgREST products only — no Realtime/Storage/Functions linked) inside `SupabaseBackend`,
which implements the `AuthService` and `RemoteLedgerService` protocols. SDK errors are mapped to domain errors there.

## Consequences
+ Keychain session storage, PKCE and token refresh come from the maintained SDK.
+ Features and the sync engine are testable with in-memory fakes; the backend can be replaced by changing one module.
+ Linking only two products keeps the binary small (6.2 MB stripped, all static).
