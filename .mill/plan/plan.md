# Plan — #6: docs(concept): switch bundled embedder to EmbeddingGemma 2

Satisfies Carder acceptance criteria: AC #1–#5 (see `## Refined by Carder` on issue #6). Only file touched: `docs/concept.md`, per Carder's affected-files table.

Doc-only change, so "tests" are `grep` checks against `docs/concept.md`; each unit's check must fail before its edit and pass after. `go test ./...` from `app/` stays green throughout (no code touched).

## Phases

1. **Concept doc update** — swap embedder facts, prompts, license, API model names, and roadmap entries. See `phase-1.md`.
