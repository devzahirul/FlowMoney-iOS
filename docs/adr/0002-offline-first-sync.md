# ADR-0002: Offline-first ledger with an outbox and "changed since" pulls

**Status:** Accepted · 2026-09-28

## Context
People add expenses in shops, on the subway, on planes. Losing an entry or showing a spinner is unacceptable.

## Decision
Local state is the source of truth for the UI. Every write goes to disk + an outbox keyed by row (coalescing edits).
Sync = push outbox (idempotent upserts, client UUIDs) → pull rows with server `updated_at > cursor − 60 s`.
Soft deletes propagate as tombstones. Pending local edits win over incoming server copies (last writer wins).
Recurring postings and budgets use deterministic IDs so concurrent offline devices converge on one row.

## Consequences
+ Instant UI, full offline support, no lost edits (tested, including edits during an in-flight push).
+ Simple server: plain tables + RLS, no custom sync endpoint.
− Last-writer-wins at row level (no field-level merge). Acceptable for a single-user ledger.
− Tombstones accumulate; a scheduled purge of rows deleted > 1 year ago is the follow-up.
