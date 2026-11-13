# Phase 1 — ADRs and index

Writes every ADR listed in `plan.md` ("ADR set") using the shared template, then the index. Units are grouped by topic so each commit is reviewable in one sitting. Commit style: `docs(adr): …`.

### Unit 1.1 — Embedder ADRs

**Test first:** `check 19-embeddinggemma-300m.md 19-local-embedder-default.md 6-embeddinggemma-2.md` (shared check in `plan.md`), plus `grep -qx 'Status: superseded by 6-embeddinggemma-2.md' docs/adr/19-embeddinggemma-300m.md`. Fails now because `docs/adr/` does not exist.

**Corner cases:**
- `19-embeddinggemma-300m.md`: Status is `superseded by 6-embeddinggemma-2.md`, not `accepted` (AC #4), and its Source line points at `62b61ba^` because current §13.1 no longer holds the old text.
- `19-embeddinggemma-300m.md`: the old §13.1 names no rival small model. Do **not** invent one (AC #2). The only rejected option it can cite is the one the old text implies: an API model as default ("~80% of the best API models"). If that reads as a duplicate of `19-local-embedder-default.md`, write `- None named in the source.` and accept that the shared check's rejected-option line flags this one file. AC #4 requires this ADR anyway.
- `6-embeddinggemma-2.md`: the numbers (68.76 vs 78.68, Gemma ToU vs Apache 2.0) come from the issue #6 body, and the ADR cites `Ticket: #6` with no Source line.

**Then:** create `docs/adr/` and write the three files from the template, using the anchors in `plan.md`.

**End state:** shared check prints nothing (except the documented 300M case, if it applies). `cd app && go test ./...` passes.

### Unit 1.2 — Storage, graph and concurrency ADRs

**Test first:** `check 19-age-graph-in-postgres.md 19-tree-sitter-analyzers.md 19-graph-rebuild-on-restore.md 19-concurrency-mvcc-advisory-locks.md 19-hybrid-recall-rrf.md`. Fails because the files don't exist.

**Corner cases:**
- Every rejected option has its §-anchor text in `docs/concept.md`. Check with `grep -n` per option before writing it, e.g. `grep -n 'Neo4j\|recursive-CTE' docs/concept.md`, and `grep -n 'chosen over regex' docs/concept.md`.
- `19-concurrency-…`: don't cite CLAUDE.md's "exit cleanly, not block" as a rejected option. CLAUDE.md is not a cited source, so only §17 text counts.
- `19-hybrid-recall-rrf.md`: the rejected single-path options take their "why not" from the §6 Weakness column word for word, with no extra benchmark claims.

**Then:** write the five files from the template.

**End state:** shared check prints nothing. `cd app && go test ./...` passes.

### Unit 1.3 — Principle and ticket ADRs

**Test first:** `check 19-storage-only-completions.md 19-free-form-tags.md 7-session-summaries.md 8-global-memory-space.md`. Fails because the files don't exist.

**Corner cases:**
- `7-…` and `8-…` use `Ticket: #7` / `Ticket: #8` with no Source line, and their rejected options trace to the issue text (`gh issue view 7` / `8`) or to the concept sections named in `plan.md`.
- `8-global-memory-space.md`: Consequences must state the narrow isolation exception (only `_global` may be read cross-project, §2.6), so it can't be read as weakening "cross-project leaks are bugs".

**Then:** write the four files from the template.

**End state:** shared check prints nothing. `cd app && go test ./...` passes.

### Unit 1.4 — ADR index and final sweep

**Test first:**
```sh
diff <(ls docs/adr | grep -v '^README.md$') \
     <(grep -oE '\]\([0-9]+-[a-z0-9-]+\.md\)' docs/adr/README.md | tr -d '()]')
check $(ls docs/adr | grep -v '^README.md$')
git diff --quiet origin/develop -- docs/concept.md && echo concept-unchanged
```
Fails now because `README.md` does not exist.

**Corner cases:**
- Filename order means `ls` order (C locale), so all `19-…` entries come before `6-…`, `7-…`, `8-…`. Don't sort numerically.
- Every entry is a relative link (`[title](19-…md)`) plus a one-line description. The 300M entry says it is superseded.
- `docs/concept.md` is byte-identical to `origin/develop` (AC #5).
- No `docs/README.md` is created (ticket Out).

**Then:** write `docs/adr/README.md`: a one-line intro, then a list with one bullet per ADR in `ls` order.

**End state:** the diff prints nothing, the check prints nothing (except the documented 300M case, if it applies), `concept-unchanged` is printed, and `cd app && go test ./...` passes.
