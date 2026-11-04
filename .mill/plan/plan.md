# Plan — #8: docs(concept): cross-project `_global` memory space

Satisfies Carder acceptance criteria: AC #1–#4 (see `## Refined by Carder` on #8). Only file touched: `docs/concept.md`, per Carder's affected-files table.

## Phases

1. **Specify `_global` in the concept** — define the space, its read/write surface, and its lifecycle across §2, §3, §4.3, §6, §7, §10, §16, §18.5, §22. See `phase-1.md`.

One phase only: a single-file docs change whose sections must land together to stay consistent. Units are ordered so each commit leaves the doc self-consistent.

## Verification approach (docs-only)

There's no code, so each unit's "test first" is a `grep` check on `docs/concept.md` that fails before the edit and passes after. `cd app && go test ./...` must still pass (nothing under `app/` changes).

## Decisions the Spinner should apply (flag any disagreement on the MR)

- **Schema shape (§4.3):** `_global` is a seeded `projects` row. `repo_root` and `graph_name` become nullable, with `CHECK ((name = '_global') = (repo_root IS NULL AND graph_name IS NULL))`. `entries` gets `CHECK (NOT (project = '_global' AND category = 'code'))`. A DB constraint is used instead of app-only validation because the database is the trust boundary shared by every agent. `events.project` keeps its FK, and `_global` events log under `_global`.
- **Isolation stated narrowly (§2 #6):** `_global` is the **only** scope a recall may read besides the current project. Cross-project reads between registered projects stay a bug.
- **Backup/export placement:** the ticket's section list leaves out §14, so backup/export behaviour for `_global` goes in §7.2 (operator CLI) next to the `backup`/`export`/`restore` lines. If the reviewer would rather have it in §14, moving it is a small change.
- **Tags (§18.5):** `_global` has its own tag namespace. A `--tag` recall filter applies to both scopes, matched independently in each.
- **#7 coordination:** #7 has no commits on its branch yet. Keep the §10 edit to new bullets inside §10.1's existing list so a later #7 rebase only conflicts on adjacent lines.
