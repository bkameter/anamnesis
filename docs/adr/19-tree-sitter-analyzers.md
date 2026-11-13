# Tree-sitter static analyzers for graph edges

Status: accepted
Ticket: #19
Source: docs/concept.md §5.4

## Context
Graph edges must come from the code itself. §5.4 requires one analyzer per language that survives multi-line imports, re-exports, JSX-inside-TS, template-string dynamic imports and Dart null-safety syntax.

## Decision
Derive edges by deterministic static analysis with one tree-sitter analyzer per language.

## Rejected options
- **Regex**: tree-sitter is "chosen over regex for robustness on edge cases" such as the ones listed above (§5.4).
- **LLM-derived edges**: edges are "never LLM calls" (§5.4).

## Consequences
- Adding a language means one `Analyze` implementation plus tree-sitter queries.
- Tree-sitter needs CGo in the build.
- Files in unsupported languages still get `Module` nodes without outgoing edges.
