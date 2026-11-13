# Free-form tags, no controlled vocabulary

Status: accepted
Ticket: #19
Source: docs/concept.md §18.2

## Context
Agents tag entries on write. §18 has to decide between letting them invent tags and requiring an approved list.

## Decision
Tags are free-form with write-time normalization. Sprawl is handled afterwards with dedicated tooling (§18.3).

## Rejected options
- **Controlled vocabulary or registry**: forcing a registry update before `remember` breaks the flow; "the cost of sprawl is lower than the cost of friction" (§18.2).

## Consequences
- Tags drift and need cleanup tooling (list, rename, merge).
- `remember` never fails because of an unknown tag.
