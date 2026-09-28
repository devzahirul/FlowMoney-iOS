# ADR-0003: One encrypted JSON snapshot per user instead of Core Data / SwiftData

**Status:** Accepted · 2026-09-28

## Context
A personal ledger is a few thousand rows. We need atomic writes, encryption at rest and trivial testing.

## Decision
Persist `LedgerState` (a Codable value type) as one file per user, written atomically with
`completeFileProtectionUntilFirstUserAuthentication`. Load happens in the repository's async init (off the main actor).

## Consequences
+ No migration machinery or managed-object threading rules; the store is a value type tested like any other.
+ A corrupt or newer-schema file falls back to a clean state and re-pulls from the server.
− Whole-file rewrite per change. Fine up to ~20k rows; beyond that, move to SQLite (GRDB) behind the same
  `LedgerPersistence` protocol — no feature code changes.
