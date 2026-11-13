# Reserved `_global` memory space

Status: accepted
Ticket: #8

## Context
All memory was strictly per project, so general knowledge was duplicated into every project or lost (issue #8 Problem). The concept's principle is that cross-project leaks are bugs (§2.6).

## Decision
A reserved pseudo-project `_global` with no repo root and no AGE graph, allowing `conv:`, `task:` and `arch:` entries. `recall` includes it by default; writes need `--global` (§3).

## Rejected options
- **Strictly per-project memory**: knowledge is duplicated or lost (issue #8 Problem).
- **A `promote` command**: `forget` + `remember --global` suffices (issue #8 Out).
- **`code:` entries in `_global`**: they are file-paired and need a repo (issue #8 In, §3).

## Consequences
- Narrow isolation exception: only `_global` may be read across projects, alongside the current project (§2.6). Every other cross-project read is still a bug.
- The schema enforces it: CHECK constraints on `projects` and `entries` (§4.3).
- `init` refuses the name `_global`; graph operations against it error out.
