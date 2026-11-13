# Dependency graph in Apache AGE inside Postgres

Status: accepted
Ticket: #19
Source: docs/concept.md §5.1

## Context
Entries describe what; the dependency graph describes how files connect. The graph needs a query language that handles deep traversals on large codebases.

## Decision
Store the graph in Apache AGE, queried with openCypher, in the same Postgres instance as the entries.

## Rejected options
- **Neo4j**: same query language, but a second database to back up and secure (§5.1).
- **Recursive CTEs**: become "gymnastics" past depth 2; Cypher one-liners replace them (§5.1).

## Consequences
- One database to back up and secure.
- Graph features depend on the AGE extension, so they must degrade when it is missing.
- Graph queries are openCypher, not SQL.
