# ADR-0004: Integer minor units and a single-currency ledger

**Status:** Accepted · 2026-09-28

## Decision
`Money` stores `Int64` minor units (cents); the currency lives on the profile. Decimal input rounds half-even to the
currency's precision (0 for JPY). Postgres uses `bigint` with CHECK constraints.

## Consequences
+ Exact sums, 1:1 wire format with the database, trivially fast.
− Multi-currency accounts would need FX rates and per-amount currency — out of scope; changing currency re-labels
  amounts rather than converting them (stated in Settings).
