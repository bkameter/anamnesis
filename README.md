# Anamnesis

> *anamnesis* (ἀνάμνησις): recollection; the act of calling back to mind what was once known.

Persistent, agent-agnostic memory for coding agents. Any tool that can shell out — Claude Code, Codex, Cursor, Aider, or a custom harness — consults Anamnesis before touching the filesystem, and contributes back after finishing a task. Built for **large codebases**: tens of thousands of files, hundreds of thousands of graph edges, memory that grows across years of work.

## Status

Concept phase. The full design lives in [`docs/concept.md`](docs/concept.md). No implementation yet.

## In short

- **Storage:** PostgreSQL 17 with `pgvector` (semantic), `pg_trgm` (fuzzy), and Apache AGE (openCypher graph) — one local instance serves every project on the machine.
- **Embeddings:** bundled local model (EmbeddingGemma-300M INT8 ONNX) by default; optional API providers (Voyage, OpenAI, Cohere, Ollama) for higher-quality vectors.
- **Completions:** never called by Anamnesis. Entry summaries are drafted by the agent that's already running.
- **Four memory categories:** `code:`, `arch:`, `task:`, `conv:` — each with distinct staleness and pruning semantics.
- **Degrades gracefully.** Postgres down, embedding provider unreachable, AGE extension missing — the agent falls back to normal file reads. Anamnesis is an optimisation, never a critical path.

See the concept doc for storage schema, scan pipeline, recall API, secret scrubbing, dependency-graph semantics, and the full CLI surface.

## Repository layout

This is a monorepo with two top-level components:

```
.
├── app/         # Go module — the anamnesis CLI and its packages
├── docker/      # Local-dev Postgres 17 + pgvector + pg_trgm + Apache AGE stack,
│                # plus the optional Apache AGE viewer
├── docs/        # Design documents (concept.md is the current source of truth)
├── CLAUDE.md    # Agent-guidance for Claude Code
├── LICENSE
└── README.md
```

- Go code, tests, and build commands all run from [`app/`](app/) — see [`app/README.md`](app/README.md).
- The local database + viewer live in [`docker/`](docker/) — see [`docker/README.md`](docker/README.md).

## License

See [LICENSE](LICENSE).
