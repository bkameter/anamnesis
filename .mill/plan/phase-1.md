# Phase 1 — Concept update

All edits are to `docs/concept.md`. The units are ordered so the normative description (storage shape, then the flow) lands first and the cross-references (§10, §19, §20, §21) then point at it. Every unit ends with a self-consistent document.

Run each grep check from the repo root. "Fails now" means the grep finds nothing (or finds the old text) before the edit.

### Unit 1.1 — Storage shape: one `task:` entry per session (AC #3)

**Test first:** `grep -n 'session' docs/concept.md` in §3 and §9.1 — asserts that (a) the §3 Task row names the per-session key form next to `task:YYYY-MM-DD-<slug>`, (b) §9.1 no longer says "not per session", and (c) the fixed sections `Decisions`, `Open / next steps`, `Gotchas` appear. Fails now because §9.1 line "one entry per logical completed task … not per file, not per session" exists and no section names appear.

**Corner cases:**
- A session that spans midnight: the key must stay stable, so the date in the key is the session's start date and isn't recomputed on each approval.
- A session that also finishes a task: the per-session summary and the per-task `remember-task` entry coexist with distinct keys. Neither replaces the other.
- An empty section: say whether it's omitted or written as "none" (pick one).
- The 100–500-token size constraint from §3 still applies to the session entry.

**Then:** In §3, extend the Task row (or add one sentence under the table) with the session-key convention. Suggested form: `task:<YYYY-MM-DD>-session-<session-id>`, keyed by `ANAMNESIS_SESSION_ID` (§15.1/§19.1 already define it), so it keeps the `task:` prefix and the never-age-pruned semantics. In §9.1, reword the granularity line: per-task entries stay as they are, and per-session summaries are a second, separate `task:` entry. Specify that each approval overwrites the same key (an upsert via the existing `anamnesis remember --key … --category task`), so no new CLI command is needed. Specify the three fixed sections. Don't restate the Carder notes. Reference §9.5 (Unit 1.2) for the flow.

**End state:** grep checks pass; `cd app && go test ./...` passes.

### Unit 1.2 — Approval-gated flow: periodic prompt and manual trigger (AC #1, #4)

**Test first:** `grep -n '### 9.5' docs/concept.md` and `grep -n -i 'save / discard / later' docs/concept.md` — assert that a new §9.5 "Session summaries (user-approved)" exists. It must describe a throttled `Stop` hook (default 30 min of active session, configurable), a manual "save the session" skill trigger, and the explicit statement that nothing is written without user approval. Fails now because §9 has only 9.1–9.4.

**Corner cases:**
- "later" defers without writing and without resetting the throttle to a full fresh window (state what happens, e.g. re-prompt at the next throttle window).
- "discard" records the decision point, so the next prompt only covers material newer than it.
- The throttle counts *active* session time (define it: time with agent turns, not wall-clock idle).
- Agents without hooks (Codex, Aider) can only use the manual trigger. Say so explicitly.
- The hook only *prompts the agent* to draft and ask. It never calls `remember` itself. Anamnesis never drafts (storage-only, §2.2).
- `ANAMNESIS_ENABLED=false` or Postgres down: the hook is a no-op (ties to Unit 1.4's §20 row).

**Then:** Add §9.5 after §9.4. Update §9's intro "Three update mechanisms" count to match. Describe the draft → show the user → save / discard / later loop, the throttled `Stop` hook, and the manual trigger. Each save is an upsert of the Unit 1.1 key. Fix the §9.3 sentence "nag on `Stop`" to point at §9.5 so the two `Stop` hook descriptions don't conflict (per Carder's note).

**End state:** grep checks pass; `cd app && go test ./...` passes.

### Unit 1.3 — Session-end pending marker (AC #2, #4)

**Test first:** `grep -n -i 'SessionEnd' docs/concept.md` and `grep -n -i 'pending marker' docs/concept.md` — assert that §9.5 describes the `SessionEnd` hook writing a marker (session id + transcript path) with no memory write. The marker must be offered on up to 3 later session starts in the same project, then discarded, and skipped when nothing is new since the last decision. Fails now because neither term appears.

**Corner cases:**
- The marker location is local, per project, and outside Postgres (e.g. under the gitignored `.anamnesis/` dir), so writing it is not a memory write and works with Postgres down.
- The counter increments on every session start where the marker is offered, including when the user picks "later". It's discarded after the 3rd offer.
- "Nothing new since the last decision": compare against the last save/discard for that session (an approval in-session clears or skips the marker).
- A transcript that's missing at offer time (Claude Code's 30-day deletion) or a hard crash with no `SessionEnd` is out of scope. Say it in one line and drop the marker silently.
- Several pending markers (several sessions ended unsummarised): offered one per session or together. Pick one.
- A marker from project A must never be offered in project B (multi-project invariant).

**Then:** Extend §9.5 with the safety-net subsection covering marker contents, location, offer rule, 3-offer cap and the skip condition. Note that background/headless summarisation at session end is deliberately not done.

**End state:** grep checks pass; `cd app && go test ./...` passes.

### Unit 1.4 — Align §10, §19, §20, §21 (AC #1, #4)

**Test first:** grep assertions:
- §10.1 skill bullets mention the "save the session" trigger and the start-of-session pending-marker check, and the `install-hooks` line lists the `Stop`/`SessionEnd` hooks.
- §10.2 mentions the manual trigger for hookless agents.
- §19.2 has a config key for the throttle (e.g. `updates.session_summary_interval: 30m`).
- §20 has rows for the session-summary hooks/marker failing.
- §20's "Agent skips `remember`" row no longer says "`Stop` hook nags more loudly".
- §21's chat-history bullet says summaries yes, chat history no.

Fails now because none of these exist and the §20/§21 texts are the old wording.

**Corner cases:**
- §21 must still exclude raw transcripts and chat history. Only the user-approved summary is stored.
- §21's "No scheduled background jobs" stays true: the hooks are agent-session events, not a daemon. Say so if it's ambiguous.
- `install-hooks` defaults: the new hooks are opt-in, like `claude_code_hooks_default: false`. State this explicitly.
- The §20 degradation row covers a missing or broken marker file, a hook failure, and Postgres down at save time (the summary isn't lost silently: the agent reports it and the user can retry).

**Then:** Make the minimal wording edits in §10.1, §10.2, §19.2 (one config key, with a comment), §20 (one new row plus the edited `Stop` row), and §21 (reword the chat-history bullet). After the edits, grep the whole file for `per session`, `Stop`, `chat-history` and `session state` to confirm no leftover contradictions.

**End state:** grep checks pass; a full read-through of §2, §3, §9, §10, §19, §20, §21 finds no contradiction with storage-only (§2.2) or the non-goals; `cd app && go test ./...` passes.
