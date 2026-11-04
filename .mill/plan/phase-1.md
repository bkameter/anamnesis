# Phase 1 — Specify `_global` in the concept

The whole ticket: three commit-sized edits to `docs/concept.md`, grouped by acceptance criterion so each commit is reviewable and self-consistent.

### Unit 1.1 — Define the `_global` space (§2, §3, §4.3) — AC #1, isolation half of AC #4

**Test first:** `grep -n '_global' docs/concept.md` returns hits in §2 (principle 6), §3, and §4.3 (a `CHECK` naming `_global` and `code`). Fails now: `_global` appears nowhere in the file.

**Corner cases:**
- `init --name _global` is refused. §7.2's `init` line gets a comment.
- A `code:` write targeting `_global` is rejected by the DB constraint *and* the CLI with a clear error. It is never silently rerouted to the project.
- `_global` has no repo root and no AGE graph. §4.3 states that `deps`/graph ops against it error out, the same way they do for "AGE missing".
- Principle 6 keeps "cross-project leaks are bugs" for every scope pair except project↔`_global` reads.

**Then:** Amend §2 principle 6 with one sentence on the single `_global` exception. In §3, add a short paragraph after the category table listing which categories `_global` allows (`conv:` incl. best practices, `task:`, `arch:`; not `code:`). In §4.3, make `repo_root`/`graph_name` nullable, add the two `CHECK`s and the seed row, and add one sentence of prose under the schema block.

**End state:** `cd app && go test ./...` passes. The doc reads consistently through §4.

### Unit 1.2 — Read/write surface and skill guidance (§6, §7, §10) — AC #2, AC #3

**Test first:** `grep -n -- '--no-global\|--global\|\[global\]' docs/concept.md` returns hits in §6, §7.1 (`recall`, `remember`, `remember-task`, `remember-batch`), and §10.1. Fails now: none of these flags or markers exist.

**Corner cases:**
- `recall` fuses project and `_global` in **one** RRF ranking (§6/§6.3: `project IN ($project, '_global')`, not two separate result lists). `_global` hits are marked `[global]` in text output and with `"scope":"global"` in JSON (§7.3 only if it has an output example to touch; otherwise §7.1).
- `--no-global` excludes `_global`. Outside any project, `--no-global` has no scope left, so recall returns empty and exits 0. It doesn't fail.
- `--file` / `--package` / `deps` filters are project-only. `_global` holds no `code:` rows, so it contributes nothing to them. State this, but add no special-case code path.
- Outside any registered project, cwd resolution falls back to `_global`. `status` reports `_global` and exits 0, so the skill stays active (§7.1 `status` line, §10.1 Trigger/Discovery). `--project` still overrides.
- `--global` inside a project writes to `_global`. Outside a project it's a no-op (already global). `--global` plus `--category code` is refused (ties to Unit 1.1). For `remember-batch`, `--global` applies to the whole batch, with no per-row scope.
- Skill guidance in §10.1: use `--global` only for knowledge that isn't project-specific. Session-summary drafts propose project vs global per entry for the user to confirm.

**Then:** Update the §6 intro and the §6.3 RRF sketch's scope predicate, plus one sentence on the `[global]` marker. Add `--global` / `--no-global` to the §7.1 command block, and change the scope-resolution sentence after it to "nearest `.anamnesis/project.yaml`, else `_global`". Add two bullets to §10.1 and adjust its Trigger/Discovery wording.

**End state:** `cd app && go test ./...` passes. §6/§7/§10 agree on flags and defaults.

### Unit 1.3 — Lifecycle and roadmap (§7.2, §16, §18.5, §22) — AC #4

**Test first:** `grep -n '_global' docs/concept.md` additionally hits §7.2 (backup/export/restore/project lines), §16, §18.5, and §22. Fails now: Units 1.1–1.2 don't touch these sections.

**Corner cases:**
- `backup` (default, current project) excludes `_global`. `--project _global` backs it up alone. `--all-projects` includes it. `restore` of `_global` skips the graph rebuild (no graph, no repo root) and needs no `--skip-graph`.
- `export` includes `_global` entries only when they're in scope (`--project _global` or all-projects), tagged with their project like any other row.
- `project remove _global` is refused, because `_global` is seeded and permanent. `project list` shows it, marked as reserved.
- Prune Tier 2 (`--orphans`) never matches `_global`, since it has no file-paired entries. Tiers 1 and 3 apply to it unchanged, with existing `task:`/`conv:` exclusions. Prune targets `_global` only via `--project _global`.
- §18.5: `_global` is its own tag namespace. `tags rename/merge` act on one scope at a time.
- §22: add one "v1 ships" bullet. `promote`, team-shared global, and project/global ranking weights stay out. List only "ranking weights between project and global results" under "Unresolved, deferred" (the ticket names it Out, and it's a genuine open question). Cross-project graph queries are already v2, so leave that unchanged.

**Then:** Add `_global` comments/notes to the §7.2 Data and Project-setup lines. Add a short `_global` paragraph to §16 (after 16.3 or as 16.7). Replace the §18.5 sentence with the two-namespace rule. Add the §22 bullets.

**End state:** `cd app && go test ./...` passes. Final check: `grep -c '_global' docs/concept.md` > 0 in each of the nine ticket sections, and a read-through finds no sentence implying a registered project can read another registered project.
