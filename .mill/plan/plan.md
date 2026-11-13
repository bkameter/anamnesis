# Plan — #19: Record existing design decisions as ADRs

Satisfies Carder acceptance criteria: AC #1–#5 (see `## Refined by Carder` on #19).

Docs-only. No Go code changes, so `cd app && go test ./...` stays green trivially; each unit's "test first" is a shell check against `docs/adr/`.

## Phases

1. **ADRs and index**: write the 13 ADRs below plus `docs/adr/README.md`. See `phase-1.md`.

One phase only. The units are independent batches of Markdown files, and none of them needs another phase to exist first.

## ADR set (decided here, so the Spinner doesn't re-select)

Selection rule: Carder AC #1 (the threshold, plus a rejected option named or clearly implied in the source). Every "Rejected options" line must quote or paraphrase the anchor given here (AC #2). If the Spinner can't find the anchor text, drop that line, and if no lines are left, drop that ADR.

| File | Ticket | Source anchor(s) for the rejected options |
|---|---|---|
| `19-age-graph-in-postgres.md` | #19 | §5.1: Neo4j (would add a second database to back up and secure), recursive CTEs (become "gymnastics" past depth 2) |
| `19-concurrency-mvcc-advisory-locks.md` | #19 | §17.1: explicit locking on `remember`/`recall`/`forget`/`deps`. §17.4: isolation stricter than `READ COMMITTED` |
| `19-embeddinggemma-300m.md` | #19 | Old §13.1 at `62b61ba^` (`git show 62b61ba^:docs/concept.md`). Status `superseded by 6-embeddinggemma-2.md` (AC #4) |
| `19-graph-rebuild-on-restore.md` | #19 | §14 intro and §14.1: restoring AGE's internal schemas, or shipping the graph in the backup (flaky across AGE versions) |
| `19-hybrid-recall-rrf.md` | #19 | §6 path table: tsvector-only (misses synonyms and typos), pg_trgm-only (no semantics), pgvector-only (needs a model) |
| `19-local-embedder-default.md` | #19 | §2.2, §13.1, §13.2: an API provider as the default (needs API keys and network; kept as opt-in) |
| `19-storage-only-completions.md` | #19 | §2.2, §21: Anamnesis calling a completion LLM to draft summaries (the running agent already pays for its model and context) |
| `19-free-form-tags.md` | #19 | §18.2: controlled vocabulary or registry (friction costs more than sprawl) |
| `19-tree-sitter-analyzers.md` | #19 | §5.4: regex (breaks on the listed edge cases), LLM-derived edges ("never LLM calls") |
| `6-embeddinggemma-2.md` | #6 | Issue #6 body: keep EmbeddingGemma-300M (Gemma Terms of Use, MTEB code 68.76 vs 78.68, 2K context) |
| `7-session-summaries.md` | #7 | Issue #7 Out list and §9.5 "Deliberately not covered": writing without approval, background or headless summarisation. Issue #7 Carder notes quoting old §9.1: task-only entries ("not per session"). §21: storing chat history or raw transcripts |
| `8-global-memory-space.md` | #8 | Issue #8 Problem: strictly per-project memory (duplicated or lost). Issue #8 Out: a `promote` command (`forget` + `remember --global` suffices). Issue #8 In and §3: `code:` in `_global` (file-paired, needs a repo) |

Concept-sourced ADRs carry `Source: docs/concept.md §<n>`. For `19-embeddinggemma-300m.md` the line is `Source: docs/concept.md §13.1 (as of 62b61ba^)`, because the current concept no longer has that text.

**Left out on purpose** (reviewer: say so if any of these should be in):
- #5 / PR #12: no alternatives named (per Carder).
- MCP server (§10.4, §21) and per-project embedding dimensions (§13.8): both are deferred roadmap items, which the ticket's Out list excludes.
- Port 55432 (§4.2): config that is cheap to change, so it misses the "hard to reverse" bar.
- Scrubber hard-block (§11), no downgrade path (§12.3), backup as plain SQL (§14.1): the source names no alternative.

## Shared ADR template

```markdown
# <Decision title>

Status: accepted
Ticket: #<n>
Source: docs/concept.md §<n>        <!-- only for Ticket: #19 -->

## Context
<2–4 sentences, pointing at the source.>

## Decision
<1–3 sentences.>

## Rejected options
- **<option>**: <why not, from the source>.

## Consequences
<2–4 bullets or sentences.>
```

## Shared check (used by every unit)

```sh
# usage: check <file>...   (run from repo root)
check() { for f in "$@"; do p=docs/adr/$f; test -f "$p" || { echo "MISSING $p"; continue; }
  for h in '^Status: (accepted|superseded by [0-9]+-[a-z0-9-]+\.md)$' '^Ticket: #[0-9]+$' \
           '^## Context' '^## Decision' '^## Rejected options' '^## Consequences'; do
    grep -qE "$h" "$p" || echo "$p lacks $h"; done
  grep -q '^Ticket: #19$' "$p" && { grep -qE '^Source: docs/concept\.md §[0-9]' "$p" || echo "$p lacks Source"; }
  awk '/^## Rejected options/{r=1;next}/^## /{r=0}r&&/^- /{n++}END{exit n==0}' "$p" || echo "$p has no rejected option"
done; }
```
Empty output means pass.
