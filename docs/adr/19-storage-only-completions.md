# Storage-only for completions

Status: accepted
Ticket: #19
Source: docs/concept.md §2.2

## Context
Entry summaries need an LLM to write them. §2.2 and §21 ask who should run it.

## Decision
Anamnesis never calls a completion LLM. The agent that is already running drafts the summaries. Anamnesis owns the deterministic primitives and local embeddings.

## Rejected options
- **Anamnesis calling a completion LLM to draft summaries**: the running agent's model, context and token budget are already paid for by the user (§2.2).

## Consequences
- No completion API keys or provider code in Anamnesis.
- Summary quality depends on the calling agent and its skill guidance.
- Embeddings are the stated exception (§21).
