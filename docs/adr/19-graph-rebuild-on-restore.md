# Rebuild the graph from source on restore

Status: accepted
Ticket: #19
Source: docs/concept.md §14

## Context
A careless restore wrecks months of accumulated memory. §14 wants a restore path that survives AGE version mismatches and partial corruption.

## Decision
`backup` leaves the AGE graph out. `restore` rebuilds it from source.

## Rejected options
- **Restoring AGE's internal schemas**: rebuilding from source is chosen over it (§14 intro).
- **Shipping the graph in the backup**: "invites AGE restore flakiness" (§14.1).

## Consequences
- Backups are smaller and independent of the AGE version.
- The graph is rebuilt from source after restore; `restore` offers `--skip-graph` (§14.2).
- Embeddings are included by default because they are expensive to regenerate.
