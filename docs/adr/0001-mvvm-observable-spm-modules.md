# ADR-0001: MVVM with @Observable, split into SPM modules

**Status:** Accepted · 2026-09-28

## Context
A portfolio-grade finance app must be easy for another developer to pick up, fast at runtime, and testable
without a simulator. Candidates: MV, MVVM (+ Observation), TCA, VIPER.

## Decision
MVVM with `@Observable` view models (iOS 17+), business rules in a pure `Domain` module, and one SPM module per feature.

## Consequences
+ Fine-grained SwiftUI updates for free (Observation tracks per-property reads).
+ No architecture dependency; any iOS developer can read it.
+ The module graph enforces boundaries at compile time and keeps incremental builds small.
− View models are conventions, not enforced by a framework (TCA would enforce more). Mitigated by the shared
  `LedgerObserving` protocol and code review.
