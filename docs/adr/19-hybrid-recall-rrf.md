# Hybrid recall over three paths

Status: accepted
Ticket: #19
Source: docs/concept.md §6

## Context
Recall must find entries through exact keywords, typos and paraphrases. §6 compares three Postgres search paths, each with its own weakness.

## Decision
Run tsvector, pg_trgm and pgvector together and fuse their results with RRF.

## Rejected options
- **tsvector only**: misses synonyms, fails on typos (§6).
- **pg_trgm only**: no semantic understanding (§6).
- **pgvector only**: needs an embedding model (§6).

## Consequences
- Three indexes to maintain per entry.
- Recall still returns results from the other two paths when the embedder is unavailable.
