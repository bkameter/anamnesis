# CLAUDE.md

Guidance for Claude Code (and any other coding agent) working in this repo.

## Project

**Anamnesis** — persistent, agent-agnostic memory for coding agents. Backed by PostgreSQL (pgvector + pg_trgm + Apache AGE). See [`docs/concept.md`](docs/concept.md) for the full design.

## Repository layout

Monorepo. Two top-level components:

| Folder | Purpose |
|---|---|
| [`app/`](app/) | Go module (`github.com/bkameter/anamnesis/app`). CLI entry point, internal packages, migrations. |
| [`docker/`](docker/) | Local-dev stack: Postgres 17 + pgvector + pg_trgm + Apache AGE image, optional Apache AGE viewer. |
| [`docs/`](docs/) | Design documents. `concept.md` is the current source of truth; treat it as normative. |

## Commands

**All Go commands run from `app/`, not the repo root.** `go.mod` lives in `app/`.

- **Build:** `cd app && go build ./...`
- **Test:** `cd app && go test ./...`
- **Lint:** `cd app && golangci-lint run ./...`
- **Type check:** `cd app && go build ./...` (Go's compiler is the type checker)

Bringing up the local database:

- `docker compose -f docker/compose.yaml up -d`                 — database only
- `docker compose -f docker/compose.yaml --profile viewer up -d` — database + AGE viewer on <http://localhost:8089>
- `docker compose -f docker/compose.yaml down`                   — tear everything down

Default local URL: `postgres://anamnesis:anamnesis_local@localhost:55432/anamnesis`.

## Key invariants from the concept doc

Treat these as hard constraints; the design doc explains the reasoning in depth.

- **Agent-agnostic contract.** Anamnesis is a CLI + a Postgres instance. Any coding tool that can shell out can use it.
- **Storage-only for completions.** Anamnesis never calls a completion LLM. Entry summaries are drafted by the agent that's already running. Anamnesis owns the deterministic primitives: static analysis, storage, indexing, hybrid recall, graph traversal, plus **local embeddings** via a bundled ONNX model (EmbeddingGemma-300M by default).
- **Recall before read.** Canonical workflow: query memory → query the graph → read only files not covered → complete the task → write back what was learned.
- **Memory is an optimisation, not a critical path.** Every dependency must degrade gracefully — Postgres down, embedding provider unreachable, AGE extension missing, the agent falls back to normal file reads. Nothing breaks hard.
- **Four entry categories with distinct semantics:** `code:` (file-paired, content-hashed), `arch:` (cross-cutting), `task:` (lessons, never age-pruned), `conv:` (conventions). Do not collapse them.
- **Multi-project by default.** Scope via a `project` column + per-project Apache AGE graph named `proj_<sanitised-project-name>`. Cross-project leaks are bugs.
- **Human-inspectable.** Plain-text entries. Standard Postgres. `anamnesis audit` / `stats` / `doctor` / `export --format json` must always work.

## Conventions

- **Commits:** conventional commits (`feat:`, `fix:`, `chore:`, `docs:`, …).
- **Branches:** feature branches for any non-trivial change; direct commits to `main` are acceptable only for scaffolding.
- **Secrets:** writes to the store go through the scrubber unless `--force-insecure` is set, and forced writes must be tagged `source='forced-insecure'` and logged to `events`.
- **Advisory locks:** scan uses a per-project advisory lock; concurrent scan invocations must exit cleanly, not block.
- **Tests and lint:** run `go test ./...` and `golangci-lint run ./...` from `app/` before every commit.
