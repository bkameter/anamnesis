# User-approved session summaries

Status: accepted
Ticket: #7

## Context
Sessions without a finished task (discussions, research, aborted work) left nothing in memory, but the user must stay in control of what enters it (issue #7 Problem). The concept's §9.1 said task entries were "not per session".

## Decision
One `task:` entry per session, written only after explicit user approval via a throttled hook prompt or a manual trigger. A `SessionEnd` hook only leaves a pending marker (§9.5).

## Rejected options
- **Writing to memory without approval**: out of scope; no path may write without explicit user approval (issue #7 Out).
- **Background or headless summarisation at session end**: "deliberately not covered" (§9.5, issue #7 Out).
- **Task-only entries, "not per session"**: the old §9.1 behaviour that the issue changes (issue #7 Carder notes).
- **Storing chat history or raw transcripts**: raw transcripts are never stored; summaries yes, chat history no (§21).

## Consequences
- Session-end safety net keeps only a local marker, not a memory write.
- No recovery after a hard crash or after Claude Code deletes the transcript.
- Agents without hooks use the manual trigger only.
