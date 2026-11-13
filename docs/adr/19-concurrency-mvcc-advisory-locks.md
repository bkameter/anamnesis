# Concurrency: MVCC and UPSERT, no explicit locking

Status: accepted
Ticket: #19
Source: docs/concept.md §17

## Context
Many agents share one Postgres instance, so concurrent writes are normal. §17 sets the concurrency model for the entry operations.

## Decision
Rely on MVCC and `ON CONFLICT DO UPDATE` for `remember`, `recall`, `forget` and `deps`. Use advisory locks only for exclusive operations (§17.2). Run at the default `READ COMMITTED` isolation.

## Rejected options
- **Explicit locking on `remember`/`recall`/`forget`/`deps`**: row-level races already resolve correctly via UPSERT (§17.1).
- **Isolation stricter than `READ COMMITTED`**: not needed, except during migrations, which hold an advisory lock anyway (§17.4).

## Consequences
- Last-write-wins on entries; the worst case is one extra refresh cycle, and recomputing the hash on every write keeps it safe (§17.1).
- Graph edge rewrites run in a single transaction so readers never see a partial state.
