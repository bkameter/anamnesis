# Plan — #7: docs(concept): user-approved session summaries in memory

Satisfies Carder acceptance criteria: AC #1–#4 (see `## Refined by Carder` on #7).

Docs-only: every unit edits `docs/concept.md` only (per Carder's affected-files table). There's no Go code to test, so each unit's "test" is a `grep` assertion against `docs/concept.md` that fails before the edit and passes after. `cd app && go test ./...` must stay green. It's unaffected, but it's still the loom's gate.

## Phases

1. **Concept update** — specify the approval-gated session-summary flow and align §3, §9, §10, §19, §20, §21 with it. See `phase-1.md`.

One phase only: the six sections must land together to stay consistent, and none of them is an independent stage.
