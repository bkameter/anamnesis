# Anamnesis — Persistent Memory for Coding Agents

> *anamnesis* (ἀνάμνησις): recollection; the act of calling back to mind what was once known.

Anamnesis is a persistent memory system that any coding agent — Claude Code, Codex, Cursor, Aider, or a custom harness — consults before touching the filesystem, and contributes to after finishing a task. It is designed for **large codebases**: tens of thousands of files, hundreds of thousands of graph edges, memory that grows across years of work.

v1 targets a **single developer** on one machine, serving all their projects from one local Postgres instance. Multi-developer / team-shared mode is on the roadmap but not in v1.

Storage is **PostgreSQL** with three extensions: **pgvector** (semantic embeddings), **pg_trgm** (fuzzy search), and **Apache AGE** (openCypher graph database). The anamnesis binary ships with a bundled local embedding model (**EmbeddingGemma-300M**, INT8 ONNX), so semantic recall works zero-config with no API keys. Users can opt into API providers (Voyage, OpenAI, Cohere, Ollama) for higher-quality vectors.

---

## 1. Motivation

A coding agent without persistent memory restarts from zero on every task. On a small repo that's annoying. On a **large codebase** it's prohibitive: a single task typically burns 10k–50k tokens on orientation before the agent writes a useful line, and the agent often can't form a complete enough picture to reason well. It edits one file, misses the three that also need to change, and the PR comes back with review comments the agent could have anticipated.

Anamnesis fixes this by maintaining a pre-digested, searchable map of the repository that lives alongside the code. Two layers:

| Layer | Purpose | Technology |
|-------|---------|------------|
| **Entries** | Compact text summaries of files, modules, architecture, conventions, past-task lessons. Hybrid search via keyword, fuzzy match, and semantic similarity. | `entries` table + `tsvector` + `pg_trgm` + `pgvector` |
| **Dependency graph** | Imports, calls, extends, DB access, route mappings, test→source, widget trees. Enables impact analysis, traversal, cycle detection. | Apache AGE (openCypher inside Postgres) |

| Approach | Tokens per task start | Wall-clock |
|----------|----------------------|------------|
| Cold agent, naive file scan | 10k–50k | 30–120s |
| Agent with anamnesis (recall + graph + targeted reads) | 500–2k | 1–5s |

The savings compound as memory grows. At large scale the story gets better, not worse: recall latency stays roughly constant (HNSW + GIN indexes are flat in this range), while the value of each query climbs.

---

## 2. Design Principles

1. **Agent-agnostic contract.** Anamnesis is a CLI + a Postgres instance. Any coding tool that can shell out can use it. Claude Code wires in via a Skill; Codex, Aider, and others get a system-prompt snippet generated from the same source.
2. **Storage-only for completions.** Anamnesis does not call completion LLMs. Entry summaries are drafted by the *agent that's already running* — whose model, context, and token budget the user is already paying for. Anamnesis owns the deterministic primitives (static analysis, storage, indexing, hybrid recall, graph traversal) plus **embeddings**, which it computes locally by default via a bundled on-device model (see §13). No API keys required to get semantic recall working; users can opt into API providers (Voyage, OpenAI, Cohere, Ollama) if they want higher-quality vectors.
3. **Recall before read.** The canonical workflow is encoded in the skill: query memory → query the graph → read only the files not covered → complete the task → write back what was learned.
4. **Memory is an optimisation, not a critical path.** Every dependency degrades gracefully. Postgres down, embedding provider unreachable, AGE extension missing — the agent falls back to normal file reads and gets the pre-anamnesis experience. Nothing breaks hard.
5. **Human-inspectable.** Plain-text entries. Standard Postgres. `anamnesis audit` / `stats` / `doctor` show what's happening. `anamnesis export --format json` dumps everything. Nothing is opaque.
6. **Multi-project by default.** One Postgres instance holds memory for every project on the machine. Project isolation via a `project` column + per-project AGE graph. Scoping is automatic from cwd.

---

## 3. Memory Categories

Every entry belongs to one of four categories.

| Category | Key prefix | What it captures | Written by | Example |
|----------|-----------|------------------|------------|---------|
| **Code** | `code:` | What a file/module does: exports, dependencies, patterns, contracts. | Initial scan, agent opportunistic fill-in, post-edit refresh | `code:src/auth/session.ts` — "Session handling. Exports getSession(), requireSession(). Reads JWT from cookie `sid`. Throws UnauthorizedError on miss." |
| **Architecture** | `arch:` | How components connect: data flow, design decisions, invariants. | Agent after learning from docs / code reading | `arch:auth-flow` — "Middleware in src/middleware.ts rewrites to /login for unauthenticated requests to /app/*. Token refresh inline in getSession()." |
| **Task** | `task:YYYY-MM-DD-<slug>` | Lessons from completed work: what was tricky, what surprised the agent, gotchas for future sessions. | Agent after finishing a task | `task:2026-04-16-extract-jwt-verify` — "Gotcha: tests stub Date.now via vi.useFakeTimers — don't import Date.now directly." |
| **Convention** | `conv:` | Coding standards, naming rules, tooling quirks. | Human; agent when reading docs/ADRs | `conv:error-handling` — "All route handlers throw `AppError`. Never throw raw Error — the middleware won't map it." |

**Size constraint:** 100–500 tokens per summary. Long enough to be useful, short enough that a recall returning 10 entries stays under ~5k tokens of agent context.

**Category distinctions that matter for pruning and staleness:**
- `code:` entries are paired to a file; they have a `content_hash` and participate in staleness detection.
- `arch:` / `conv:` / `task:` entries are not paired to a single file's content; they don't go content-hash stale.
- `task:` entries are never pruned by age by default — their value is timeless.

---

## 4. Storage

### 4.1 PostgreSQL + extensions

A single Postgres 17 instance with three extensions:

| Extension | Purpose |
|-----------|---------|
| **pgvector** | Semantic search via HNSW-indexed cosine similarity. |
| **pg_trgm** | Fuzzy / typo-tolerant matching via trigram indexes. Contrib, always available. |
| **Apache AGE** | openCypher graph engine. One named graph per project. |

`tsvector` full-text search is a core Postgres feature; no extension needed.

### 4.2 Docker image & compose

No upstream image bundles all three, so anamnesis ships a Dockerfile that combines `pgvector/pgvector:pg17` as the base and builds Apache AGE on top. Custom port **55432** (not 5432, not 5433 — those collide with system Postgres installs on most dev machines).

```dockerfile
# docker/anamnesis-db/Dockerfile
FROM pgvector/pgvector:pg17 AS base

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential git ca-certificates postgresql-server-dev-17 \
        libreadline-dev zlib1g-dev flex bison && \
    cd /tmp && \
    git clone --branch release/PG17/1.5.0 https://github.com/apache/age.git && \
    cd age && make && make install && \
    cd / && rm -rf /tmp/age && \
    apt-get purge -y build-essential git postgresql-server-dev-17 \
        libreadline-dev zlib1g-dev flex bison && \
    apt-get autoremove -y && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN echo "shared_preload_libraries = 'age'" >> /usr/share/postgresql/postgresql.conf.sample
```

```yaml
# docker-compose.yml (embedded in the anamnesis binary, emitted by `anamnesis server init`)
services:
  anamnesis-db:
    build: ./docker/anamnesis-db
    image: anamnesis/postgres:17
    environment:
      POSTGRES_DB: anamnesis
      POSTGRES_USER: anamnesis
      POSTGRES_PASSWORD: anamnesis_local
    ports: ["55432:5432"]
    volumes:
      - anamnesis_pgdata:/var/lib/postgresql/data
      - ./docker/anamnesis-db/init.sql:/docker-entrypoint-initdb.d/00-extensions.sql
    command: >
      postgres
        -c shared_preload_libraries=age
        -c search_path=ag_catalog,public
        -c max_connections=200
        -c shared_buffers=512MB
        -c effective_cache_size=2GB
    restart: unless-stopped

  # Opt-in via the `viewer` compose profile. See prose below.
  age-viewer:
    build: https://github.com/apache/age-viewer.git#v1.0.0
    image: anamnesis/age-viewer:1.0.0
    profiles: ["viewer"]
    ports: ["127.0.0.1:8089:3001"]
    depends_on: [anamnesis-db]
    restart: unless-stopped

volumes:
  anamnesis_pgdata:
```

Apache publishes no upstream image, so the service builds from source pinned to an immutable tag (bump deliberately). It binds to loopback because the viewer has no app-level auth — anyone reaching the port gets a Postgres login form; `anamnesis deps` (§7.1) is the headless equivalent. `anamnesis server start --with-viewer` translates to `docker compose --profile viewer up`; `server stop` tears down every running service regardless of profile, so there is no separate teardown flag. Browse to <http://localhost:8089> and connect with host `anamnesis-db` (the compose service name, not `localhost`), port `5432` (in-network, not the published `55432`), database/user `anamnesis`, password `anamnesis_local`. The viewer also prompts for a graph name; each project has its own, named `proj_<sanitised-project-name>` (see §5.2) — use `anamnesis project list` (§7.2) to see project names. Useful for exploring the edge types listed in §5.2 without writing Cypher by hand.

```sql
-- docker/anamnesis-db/init.sql
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
```

Power users who run their own Postgres point anamnesis at it via `ANAMNESIS_DATABASE_URL`. The CLI installs the required extensions if it has permission; otherwise prints the exact SQL the user must run.

### 4.3 Schema

```sql
-- Managed via golang-migrate with SQL files embedded via go:embed.

CREATE TABLE projects (
    name        TEXT PRIMARY KEY,        -- "acme-monorepo", "personal-blog"
    repo_root   TEXT NOT NULL,
    graph_name  TEXT NOT NULL UNIQUE,    -- AGE graph name, sanitised from `name`
    created_at  TIMESTAMPTZ DEFAULT NOW(),
    last_scan   TIMESTAMPTZ
);

CREATE TABLE entries (
    id                      BIGSERIAL PRIMARY KEY,
    project                 TEXT NOT NULL REFERENCES projects(name) ON DELETE CASCADE,
    key                     TEXT NOT NULL,                     -- "code:src/auth/session.ts"
    category                TEXT NOT NULL,                     -- code | arch | task | conv
    summary                 TEXT NOT NULL,
    tags                    TEXT[] DEFAULT '{}',               -- normalized: lowercase kebab-case
    file_paths              TEXT[] DEFAULT '{}',
    depends_on              TEXT[] DEFAULT '{}',               -- other entry keys
    package                 TEXT,                              -- derived from path glob at scan time
    source                  TEXT,                              -- "scan" | "agent:claude-code" | "hook:post-commit" | ...
    content_hash            TEXT,                              -- git blob hash at write time; NULL for non-file entries
    embedding               vector(512),                       -- cluster-wide dimension (default; Matryoshka-truncated from 768)
    embedding_model         TEXT,                              -- which model produced this vector (e.g. "embeddinggemma-300m@512")
    embedding_generated_at  TIMESTAMPTZ,
    needs_refresh           BOOLEAN NOT NULL DEFAULT FALSE,    -- set by hooks on content-hash mismatch
    pinned                  BOOLEAN NOT NULL DEFAULT FALSE,    -- exempt from age-based pruning
    deleted_at              TIMESTAMPTZ,                       -- soft-delete tombstone
    search_vec              TSVECTOR GENERATED ALWAYS AS (
        setweight(to_tsvector('english', key),     'A') ||
        setweight(to_tsvector('english', summary), 'B') ||
        setweight(to_tsvector('english', array_to_string(tags, ' ')), 'C')
    ) STORED,
    created_at              TIMESTAMPTZ DEFAULT NOW(),
    updated_at              TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(project, key)
);

CREATE INDEX idx_entries_search         ON entries USING GIN(search_vec)          WHERE deleted_at IS NULL;
CREATE INDEX idx_entries_summary_trgm   ON entries USING GIN(summary gin_trgm_ops) WHERE deleted_at IS NULL;
CREATE INDEX idx_entries_key_trgm       ON entries USING GIN(key     gin_trgm_ops) WHERE deleted_at IS NULL;
CREATE INDEX idx_entries_embedding      ON entries USING hnsw(embedding vector_cosine_ops)
    WITH (m = 16, ef_construction = 64);
CREATE INDEX idx_entries_project_cat    ON entries(project, category) WHERE deleted_at IS NULL;
CREATE INDEX idx_entries_package        ON entries(project, package)  WHERE deleted_at IS NULL;
CREATE INDEX idx_entries_files          ON entries USING GIN(file_paths)          WHERE deleted_at IS NULL;
CREATE INDEX idx_entries_tags           ON entries USING GIN(tags)                WHERE deleted_at IS NULL;
CREATE INDEX idx_entries_needs_refresh  ON entries(project)                        WHERE needs_refresh AND deleted_at IS NULL;

CREATE TABLE events (
    id            BIGSERIAL PRIMARY KEY,
    ts            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    project       TEXT NOT NULL REFERENCES projects(name),
    op            TEXT NOT NULL,              -- recall | remember | forget | deps | scan | migrate | re-embed | backup | restore | audit | prune
    source        TEXT,                       -- "agent:claude-code" | "agent:codex" | "hook:post-commit" | "cli"
    session_id    TEXT,
    key           TEXT,
    query         TEXT,                       -- scrubbed before write
    filters       JSONB,
    result_count  INTEGER,
    latency_ms    INTEGER,
    outcome       TEXT NOT NULL,              -- ok | error | blocked
    error         TEXT,
    meta          JSONB
);
CREATE INDEX idx_events_project_ts ON events(project, ts DESC);
CREATE INDEX idx_events_key        ON events(key) WHERE key IS NOT NULL;
CREATE INDEX idx_events_op_ts      ON events(op, ts DESC);
```

**Embedding dimension is cluster-wide** (all projects share it). Default **512**, produced by the bundled **EmbeddingGemma-300M** model with Matryoshka truncation from its native 768. Selectable at install time: `--embedding-dim 768` (max quality, +50% vector storage), `512` (default), `256` (thin install, ~3% quality loss), `128` (experimental). Switching providers or dimensions later requires an explicit `anamnesis re-embed` — see §13.

**Scale targets:** sized for up to ~100k entries and ~1M graph edges without tuning. Beyond that, HNSW parameters may need adjustment.

---

## 5. Dependency Graph (Apache AGE)

### 5.1 Why AGE

Entries describe *what*. The graph describes *how it connects*. AGE gives us openCypher inside Postgres — the same query language as Neo4j with the operational benefit of one database to back up and secure. For large codebases, Cypher one-liners replace the recursive-CTE gymnastics that CTEs devolve into past depth 2.

### 5.2 Graph schema

Each project gets a named AGE graph, created on `anamnesis init`:

```sql
SELECT ag_catalog.create_graph('proj_acme_monorepo');
```

**Node type `Module`** with properties `key`, `path`, `type` (`file`/`class`/`function`/`widget`/`api_route`/`config`), `language`, `package`.

**Edge types (v1):**

| Edge | Meaning |
|------|---------|
| `IMPORTS` | Static import / require |
| `CALLS` | Runtime function call |
| `EXTENDS` | Class inheritance |
| `IMPLEMENTS` | Interface implementation |
| `DEPENDS_ON` | Package-level (pubspec.yaml / pom.xml / build.gradle / go.mod / package.json) |
| `READS` / `WRITES` | DB/storage access |
| `ROUTES_TO` | HTTP route → handler |
| `TESTS` | Test file → source file |
| `CONFIGURES` | Config file → target |
| `RENDERS` | Flutter widget parent → child (Flutter-specific) |

Edge properties: `weight`, `line`, `kind` (e.g. `default_import`, `named_import`, `dynamic_import`).

### 5.3 Representative queries

```sql
-- Impact analysis: what breaks if src/lib/jwt.ts changes? (depth 4)
SELECT * FROM cypher('proj_acme_monorepo', $$
    MATCH (c:Module {path: 'src/lib/jwt.ts'})<-[:IMPORTS|CALLS*1..4]-(affected)
    RETURN DISTINCT affected.path, affected.type
    ORDER BY affected.path
$$) AS (path agtype, type agtype);

-- Flutter widget tree descendants
SELECT * FROM cypher('proj_flutter_app', $$
    MATCH (root:Module {path: 'lib/screens/checkout.dart'})-[:RENDERS*1..6]->(child)
    RETURN DISTINCT child.path
$$) AS (path agtype);

-- Cycle detection in a subtree
SELECT * FROM cypher('proj_acme_monorepo', $$
    MATCH p = (m:Module)-[:IMPORTS*2..6]->(m)
    WHERE m.path STARTS WITH 'packages/checkout/'
    RETURN [n IN nodes(p) | n.path] AS cycle
    LIMIT 10
$$) AS (cycle agtype);

-- Hotspots
SELECT * FROM cypher('proj_acme_monorepo', $$
    MATCH (dep:Module)<-[r:IMPORTS]-(src)
    RETURN dep.path, count(r) AS imports
    ORDER BY imports DESC LIMIT 20
$$) AS (path agtype, imports agtype);
```

### 5.4 Static analyzers (tree-sitter)

Edges come from **deterministic static analysis** — never LLM calls. One analyzer per language via **tree-sitter**, chosen over regex for robustness on edge cases (multi-line imports, re-exports, JSX-inside-TS, template-string dynamic imports, Dart null-safety syntax).

**v1 languages:** TypeScript/JavaScript, Go, Java, Dart (Flutter).

- **TypeScript/JS** (`tree-sitter-typescript`, `tree-sitter-javascript`): ES imports, dynamic imports, class `extends`, Prisma accessors, barrel re-exports.
- **Go** (`tree-sitter-go`): imports, interface implementations, method receivers. `go.mod` for `DEPENDS_ON`.
- **Java** (`tree-sitter-java`): imports, `extends`/`implements`, inner-class mapping. `pom.xml` / `build.gradle` for `DEPENDS_ON`.
- **Dart/Flutter** (`tree-sitter-dart` — community-maintained; pin to a verified revision): imports, `part`/`part of`, class `extends`, widget parent-child for `RENDERS`. `pubspec.yaml` for `DEPENDS_ON`.

Python and Rust arrive in v1.1. The analyzer registry is pluggable: adding a language is one `Analyze(path, content) → (Node, []Edge)` implementation plus tree-sitter queries (`.scm`). Files in unsupported languages still get `Module` nodes (no outgoing edges) — summaries can still describe them.

**Distribution:** grammars statically linked into the single Go binary. Size ~60–80 MB. Cross-compile via `goreleaser` + `zig cc` for CGo targets.

### 5.5 Linking graph and entries

`key` is the bridge. Every `code:` entry has a corresponding `Module` node. A typical agent workflow uses both:

```
Agent: "Can I safely refactor PaymentService?"
  1. anamnesis recall "PaymentService"
       → arch entries, conventions, past-task lessons
  2. anamnesis deps --impact src/services/PaymentService.ts
       → 14 files depend on it transitively
  3. anamnesis recall --file <each impacted file>
       → per-file summaries
  Now the agent knows the shape of the change without opening any file.
```

---

## 6. Hybrid Recall

A single `anamnesis recall` runs up to three search paths and fuses them with Reciprocal Rank Fusion (RRF).

```
      anamnesis recall "session cookie jwt"
                        │
       ┌────────────────┼────────────────┐
       ▼                ▼                ▼
  ┌─────────┐     ┌──────────┐     ┌──────────┐
  │tsvector │     │ pg_trgm  │     │ pgvector │
  │ keyword │     │  fuzzy   │     │ semantic │
  └────┬────┘     └────┬─────┘     └────┬─────┘
       │               │                │
       └───────────────┼────────────────┘
                       ▼
            Reciprocal Rank Fusion
                       ▼
                Top N results
```

| Path | Strength | Weakness |
|------|----------|----------|
| **tsvector** | Exact keywords, stemming, weighted fields (`key` > `summary` > `tags`). | Misses synonyms, fails on typos. |
| **pg_trgm** | Typo-tolerant, substring match. | No semantic understanding. |
| **pgvector** | Semantic across phrasings, languages, synonyms. | Needs an embedding model — **bundled locally by default** (no API key required). |

The embedder is **owned by anamnesis and on by default**. First-run installs include a bundled local model (**EmbeddingGemma-300M**, INT8 ONNX, ~300 MB) — semantic recall works out of the box without any API keys or external services. Users who want higher-quality vectors can opt into API providers (Voyage, OpenAI, Cohere, Ollama) via config and `anamnesis re-embed`. See §13.

### 6.1 Code-aware prompt templating

EmbeddingGemma supports task-specific query prefixes that meaningfully improve retrieval quality. Anamnesis applies these automatically based on the entry/query type — the caller never sees or sets a prefix:

| Context | Applied prefix |
|---------|----------------|
| Embedding a `code:` entry | `task: code retrieval \| document: ` |
| Embedding an `arch:` / `conv:` / `task:` entry | `task: search result \| document: ` |
| `recall` query with no filter | `task: search result \| query: ` |
| `recall --file <path>` or `--package <X>` (code-scoped) | `task: code retrieval \| query: ` |

When a user opts into an API provider, anamnesis drops the prefix (most API providers don't expect it) unless the provider-specific plugin declares support.

### 6.2 Query scrubbing

The recall query string is stored in the `events` table (§15). Before storage, the same high-entropy scrubber used on writes (§11) runs on the query — if the agent accidentally pastes a token into a recall query, the audit trail doesn't capture it.

### 6.3 RRF query (simplified)

Parameters: `$1` = query text, `$2` = project, `$3` = query vector, `$4` = current embedding-model tag (e.g. `embeddinggemma-300m@512`), `$5` = result limit.

```sql
WITH kw AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY ts_rank_cd(search_vec, websearch_to_tsquery('english', $1)) DESC) AS rnk
    FROM entries
    WHERE project = $2 AND deleted_at IS NULL
      AND search_vec @@ websearch_to_tsquery('english', $1)
    LIMIT 20
),
fz AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY similarity(summary, $1) DESC) AS rnk
    FROM entries
    WHERE project = $2 AND deleted_at IS NULL
      AND (summary % $1 OR key % $1)
    LIMIT 20
),
sm AS (
    SELECT id, ROW_NUMBER() OVER (ORDER BY embedding <=> $3::vector) AS rnk
    FROM entries
    WHERE project = $2 AND deleted_at IS NULL
      AND embedding IS NOT NULL
      AND embedding_model = $4              -- current configured model tag
    ORDER BY embedding <=> $3::vector
    LIMIT 20
),
fused AS (
    SELECT id,
           COALESCE(1.0/(60 + kw.rnk), 0) +
           COALESCE(1.0/(60 + fz.rnk), 0) +
           COALESCE(1.0/(60 + sm.rnk), 0) AS score
    FROM (SELECT id FROM kw UNION SELECT id FROM fz UNION SELECT id FROM sm) ids
    LEFT JOIN kw USING(id) LEFT JOIN fz USING(id) LEFT JOIN sm USING(id)
)
SELECT e.key, e.category, e.summary, e.tags, e.file_paths, e.needs_refresh, f.score
FROM fused f JOIN entries e USING(id)
ORDER BY f.score DESC LIMIT $5;
```

### 6.4 Graceful degradation

- Bundled local model fails to load (corrupt weights, ONNX runtime load error) → anamnesis logs a warning and the `sm` CTE returns nothing; tsvector + pg_trgm carry the query. `anamnesis doctor` surfaces the problem.
- API provider (if configured) unreachable → same fallback; anamnesis does not auto-switch to the bundled model for individual queries (switching providers is an explicit `re-embed` operation to keep vector space consistent).
- Partway through an embedding migration → two mechanisms keep the vector space clean. (a) On a dim change, the `ALTER COLUMN … USING NULL` step wipes every row's vector first, so rows drop from `sm` via `embedding IS NULL`. (b) On a same-dim, different-model switch (e.g. `local@512 → ollama@512`), old vectors still exist but carry the prior `embedding_model` tag; the `sm` CTE filter `embedding_model = $4` excludes them until `re-embed` has written the new model's vector. Either way, RRF continues with the other two branches for unmigrated rows. See §13.5.
- pgvector extension absent → `sm` CTE is skipped. FTS + trigram cover.
- The agent-visible contract never breaks: recall always returns something sensible, with `[stale]` markers where relevant.

---

## 7. CLI Surface

### 7.1 Agent-facing

```bash
# Hybrid recall
anamnesis recall "session cookie auth" [--limit 10] [--format text|json]
anamnesis recall --file src/auth/session.ts
anamnesis recall --tag auth,jwt                    # AND of tags
anamnesis recall --package user-service
anamnesis recall --category arch

# Write — single
anamnesis remember \
  --key "code:src/auth/verify.ts" \
  --category code \
  --tags "auth,jwt" \
  --files "src/auth/verify.ts" \
  --summary "Stateless JWT verification. Exports verifyToken(). ..."
# Scrubber runs first, then embedding, then insert.

# Write — task sugar (auto-prepends task:<today>-)
anamnesis remember-task \
  --slug extract-jwt-verify \
  --tags "auth,jwt,refactor" \
  --files "src/auth/verify.ts,src/auth/session.ts" \
  --summary "..."

# Write — batch (JSON array on stdin; whole batch fails on any scrubber hit)
cat entries.json | anamnesis remember-batch
anamnesis remember-batch --from-file entries.json

# Dependency queries
anamnesis deps src/auth/session.ts                      # outgoing
anamnesis deps --impact src/lib/jwt.ts                  # reverse
anamnesis deps --neighbourhood src/auth/session.ts --hops 2
anamnesis deps --cycles packages/checkout/
anamnesis deps --hotspots --limit 20
anamnesis deps --path-from src/pages/Checkout.tsx --to prisma.payment

# Staleness / lifecycle
anamnesis forget "code:src/legacy/old-auth.ts"          # soft-delete; prune later removes tombstone
anamnesis mark-stale "code:src/auth/session.ts"         # set needs_refresh
anamnesis remember ... --pin                            # exempt from age-based prune

# Utility
anamnesis scrub                                         # stdin → report secrets found, exit non-zero on hit
anamnesis today                                         # prints YYYY-MM-DD (for agent task-key generation)
anamnesis status                                        # project for cwd, 0 if active
```

All commands support `--format text` (default) and `--format json`. Project scope is resolved from cwd (walk up looking for `.anamnesis/project.yaml`); override with `--project`.

### 7.2 Operator-facing

```bash
# Server lifecycle (Docker Compose wrapped)
anamnesis server start|stop|status|logs            # `start` accepts --with-viewer (see §4.2)

# Project setup
anamnesis init [--at PATH] [--name NAME]           # register project, run Phase 1
anamnesis project list|remove <name>

# Scan
anamnesis scan                                     # re-run Phase 1 (graph only, deterministic)
anamnesis scan --changed                           # only files changed since last scan
anamnesis scan --file <path>                       # single file (used by PostToolUse hook)

# Health
anamnesis doctor                                   # diagnostic: connection, extensions, graph, skill, embedding, disk, orphans
anamnesis stats                                    # entry counts, graph size, staleness, embedding coverage
anamnesis audit [--today|--since DUR] [--op X] [--key Y] [--source Z] [--outcome error]

# Tags
anamnesis tags                                     # list with counts + first/last-used dates
anamnesis tags rename <old> <new>                  # bulk rewrite under advisory lock
anamnesis tags merge <src>... <dst>

# Evolution
anamnesis migrate [--dry-run] [--apply-destructive] [--to N] [--i-have-a-backup]
anamnesis re-embed --provider X --model Y [--dim N] [--dry-run]

# Data
anamnesis export [--format json] [--include-graph] [--include-embeddings]
anamnesis import < dump.json
anamnesis backup [--project N] [--all-projects] [-o FILE] [--no-embeddings]
anamnesis restore <file> [--project N] [--overwrite] [--skip-graph] [--verify]
anamnesis prune                                    # Tier 1 only: tombstones + events past TTL
anamnesis prune --orphans [--confirm]              # Tier 2: orphaned entries
anamnesis prune --older-than 180d [--confirm]      # Tier 3: age-based, tasks/conv excluded
anamnesis prune --dry-run                          # always inspect first

# Integration
anamnesis install-skill [--format claude|codex|aider|plain] [--global|--local]
anamnesis install-hooks                            # register PostToolUse graph-refresh hook

# Config
anamnesis config get|set|list
```

### 7.3 Output format

```
┌─ code:src/auth/session.ts                                   [0.91] [stale]
│  Session handling. Exports getSession(), requireSession().
│  Reads JWT from cookie `sid`. Refreshes within 5m of expiry.
│  Throws UnauthorizedError on miss.
│  tags: auth, jwt, session
│
├─ arch:auth-flow                                              [0.84]
│  Middleware at src/middleware.ts gates /app/*. Unauthenticated
│  requests rewritten to /login with `?next=` param. Token refresh
│  is inline in getSession() — no separate refresh endpoint.
│  tags: auth, middleware, architecture
│
└─ task:2026-04-01-fix-refresh-race                            [0.72]
│  Fixed a race where two concurrent requests both triggered refresh.
│  Lock via an in-memory Map keyed by user id.
│  tags: auth, concurrency, bugfix
│
3 results (8ms, hybrid) — 1 stale
```

---

## 8. Initial Scan

Two phases. Anamnesis owns Phase 1 fully (deterministic, no LLM). Phase 2 is agent-driven and **not** part of `init` — it's opportunistic, triggered by the skill.

### 8.1 Phase 1 — graph (on `anamnesis init`)

```
anamnesis init
      │
      ▼
┌──────────────────────────────────────────────────────────┐
│ PHASE 1: Static analysis (deterministic, no AI)          │
│                                                          │
│ Register project (projects row, AGE graph).              │
│ Walk repo → filter excluded paths (.gitignore + config): │
│   detect language → tree-sitter analyze → Module + edges │
│ Bulk-upsert nodes and edges into the graph.              │
│                                                          │
│ Cost: 0 tokens. Time: seconds to a few minutes.          │
│ Big repo (50k files): ~2-5 minutes.                      │
└──────────────────────────────────────────────────────────┘
```

At the end of Phase 1, the graph is complete and `deps --impact` queries work immediately. The entries table is **empty**. That's intentional — the graph alone already makes the agent radically smarter on refactors.

### 8.2 Phase 2 — entries (agent-driven, lazy + hotspot priming)

Entry generation happens in two modes, both driven by the running agent via the skill:

**Mode A — hotspot priming (explicit, one-time per project).** The agent runs a `prime` skill action that queries `anamnesis deps --hotspots --limit 50` plus indexes `README.md`, `ADRs/`, `docs/architecture/*`. For each, the agent reads, drafts a summary, scrubs, and calls `remember-batch`. Typically 50–100 files, ~$5–15, 10 minutes of agent time. Users can skip this — the lazy mode will eventually cover high-touch areas anyway.

**Mode B — lazy fill (steady state).** Every time the agent touches a file in a real task, the skill instructs it to also summarize the file (if no recent entry exists) as part of completing the task. Over weeks of normal usage, the touched parts of the codebase become well-summarized; dead corners stay empty and never cost anything. Storage-only purity: all LLM work is the agent's, on the agent's model, with the agent's token budget.

**Full-scan escape hatch:** `anamnesis scan --full-entries` is available for users who genuinely want comprehensive coverage up front. It's not the default — it generates a work list and prompts the agent to execute it via the skill; for a 50k-file monorepo this is 20–60 minutes and $30–100.

---

## 9. Keeping Memory Current

Three update mechanisms, ordered by frequency:

### 9.1 Agent contribution (after every task)

The skill's most important instruction: before declaring a task complete, the agent records what it learned. Runs `remember-task`:

```bash
anamnesis remember-task --slug <kebab-slug> \
  --tags "<relevant,tags>" --files "<paths,touched>" \
  --summary "What you built, what surprised you, gotchas for future sessions."
```

The skill documents the guideline: *focus on non-obvious information — things a future session couldn't recover by reading the code. Skip recap. Under 300 words.*

Granularity: one entry per logical completed task (roughly PR scope), not per file, not per session.

### 9.2 Post-commit hook — graph refresh + staleness marking

On every commit (and merge), a git post-commit hook runs. **The hook itself is a thin shim that spawns a detached `anamnesis scan --changed --from-commit HEAD^..HEAD` and returns immediately** — zero blocking on the developer's terminal, no perceptible delay even on a merge that touches hundreds of files. The detached scan does the real work:

```
For each changed file (git log --name-status -M HEAD^..HEAD):
  - If rename: update entry key + file_paths; update AGE Module node; rewrite depends_on arrays in other entries.
  - If content changed: compare new git blob hash vs entry.content_hash;
    if different → UPDATE entries SET needs_refresh = true WHERE key = ...
  - Re-run analyzer → drop and re-create outgoing edges in AGE graph (single transaction per file).
  - If deleted: soft-delete entry (deleted_at = NOW()), DETACH DELETE Module node.

Graph converges within a second or two of commit on typical diffs,
seconds to ~a minute on large merges. Entries are flagged as stale,
never auto-regenerated.
```

The detached scan takes the per-project `scan` advisory lock (§17.2). If a previous scan is still running (e.g. an octopus merge followed immediately by another commit), the new invocation exits cleanly; the running scan already sees the latest HEAD via `--from-commit HEAD^..HEAD` resolved at launch time. A rare race where two back-to-back commits both lose the lock is covered by the next `anamnesis scan --changed` (manual or editor-triggered) reconciling.

**Failure mode.** If the detached process crashes or the machine sleeps mid-scan, the graph is temporarily out of date. `anamnesis doctor` reports *"N files committed since last successful scan"* and nudges the user to run `anamnesis scan --changed`. Graceful-degradation principle: the agent still functions; `deps` queries just miss the most recent edges.

**Threshold nudge.** For huge merges (default: >500 changed files), the hook prints a single stderr line — *"anamnesis: backgrounding scan of 842 files; `anamnesis stats` shows progress"* — so the developer isn't surprised if `deps` queries on the hot files stay stale for a minute.

Cost: zero tokens. The agent's next recall sees `[stale]` markers for files the user's edits touched, once the background scan commits.

### 9.3 PostToolUse hook (optional, Claude Code)

Opt-in via `anamnesis install-hooks`. When Claude Code's `Edit` or `Write` tool modifies a file, the hook runs `anamnesis scan --file <path>` — updates graph edges for the edited file *within the session* so follow-up `deps` queries in the same conversation are current. Also marks the entry `needs_refresh`.

Other hooks (auto-recall on `UserPromptSubmit`, nag on `Stop`) are available but not installed by default. Auto-inject is a footgun: injecting 10 recall results into every user prompt costs tokens the agent might not need and noise-inflates the conversation.

### 9.4 Staleness detection and refresh protocol

**Detection: git blob hash.** On every scan (manual or hook), the CLI computes the current blob hash of a file and compares against `entries.content_hash`. Mismatch → `needs_refresh = true`.

**No cascade.** If `jwt.ts` changes, `session.ts`'s entry is **not** automatically marked stale — only entries pointing at the changed file itself are flagged. Cascading at scale becomes noise that agents learn to ignore.

**Refresh is always agent-driven.** Hooks flag; they never rewrite summaries (storage-only rule). The skill instructs the agent: *if a recall result is [stale] for a file you're modifying, verify by reading the file, and after your task is complete, draft an updated summary and call `remember` to refresh.* Writing `remember` recomputes and stores the new `content_hash`, clearing the flag.

**`arch:` / `conv:` / `task:` entries are not content-hash-stale** — they have no single file. They can be marked stale manually via `anamnesis mark-stale` or pruned individually.

---

## 10. Agent Integrations

### 10.1 Claude Code (primary, Skill-based)

Ships as a Claude Code skill. `anamnesis install-skill` writes `~/.claude/skills/anamnesis/SKILL.md` (global) or `.claude/skills/anamnesis/SKILL.md` (per-project). Skill content:

- **Trigger:** when starting any coding task in a directory where `anamnesis status` succeeds.
- **Discovery:** the skill shells `anamnesis status`; zero exit means anamnesis is active, non-zero means skip the rest.
- **Recall-before-read protocol:**
  1. `anamnesis recall "<task keywords>"` before reading files.
  2. For files in scope: `anamnesis recall --file <path>`.
  3. For files to change: `anamnesis deps --impact <path>`.
  4. Read only what memory didn't cover.
- **Stale entry rule:** `[stale]` results for files you're modifying — read the file, refresh after.
- **Contribution protocol:** before declaring a task complete, call `remember-task` with non-obvious learnings.
- **Scrub discipline:** summaries describe structure, not literal values. Pipe through `anamnesis scrub` to self-check before writing.
- **Command cheat-sheet.**

`anamnesis install-hooks` optionally registers the `PostToolUse` graph-refresh hook. No other hooks by default.

### 10.2 Other agents (Codex / Aider / custom)

`anamnesis install-skill --format codex|aider|plain` prints the same protocol formatted as a system-prompt snippet. One source of truth, multiple output formats. The CLI protocol is the canonical contract; every agent just needs to know it can shell out to `anamnesis`.

### 10.3 Shared memory across agents

Because entries live in Postgres, multiple agents against the same repo share memory automatically: a task lesson written by Claude Code in the morning is available to Codex in the afternoon. Agent source is captured in the `events` table via `ANAMNESIS_SOURCE=agent:<name>` (set by the skill).

### 10.4 MCP (deferred)

Not in v1. Would offer Claude Code tighter integration (typed tools, discovery) but duplicates the CLI contract that's already serving every other agent. v1.x considers an MCP server generated from the CLI's cobra command tree.

---

## 11. Privacy & Secret Scrubbing

Task entries are the highest-risk category: an agent debugging auth might draft *"sample token: v2_abc123..."* and pipe that into memory. Even in single-dev mode, that memory could end up in a backup, an export, or (when team mode arrives) a shared store. Anamnesis hard-blocks suspected secrets at write time.

### 11.1 Patterns

The scrubber runs against every `remember` / `remember-batch` summary AND every recall query before storage (so the audit trail can't capture pasted secrets either):

- **Provider-key shapes** anchored on full format: `sk-[A-Za-z0-9]{40,}`, `sk_live_[A-Za-z0-9]{20,}`, `ghp_[A-Za-z0-9]{36}`, `AIzaSy[A-Za-z0-9_-]{33}`, `AKIA[A-Z0-9]{16}`, `xoxb-[A-Za-z0-9-]{40,}`.
- **Generic high-entropy strings:** any contiguous `[A-Za-z0-9+/=_-]{32,}` above a Shannon-entropy threshold.
- **Private-key headers:** `-----BEGIN .* PRIVATE KEY-----`.
- **Secret-in-text framings:** `(password|secret|token|api[_-]?key)\s*[:=]\s*['"]?[^\s'"]{8,}`.
- Patterns live in a YAML config shipped with the binary; users append project-specific ones via `scrubber.extra_patterns`.

**Allowlist for the generic high-entropy rule.** The high-entropy regex hits a lot of non-secret shapes common in code summaries — git SHAs, UUIDs, content hashes, npm integrity digests. These are explicit skips, not entropy-tuned away:

- Git object SHAs: `\b[0-9a-f]{7,40}\b` when the surrounding text contains *"commit"*, *"sha"*, *"blob"*, *"tree"*, or a backtick-delimited inline context.
- UUIDs v1–v5: `\b[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\b`.
- Subresource integrity / content hashes: strings prefixed `sha256-`, `sha384-`, `sha512-`.
- Base64-ish short runs (<44 chars) that decode to printable ASCII and lack prefix markers (per §11.1 secret-framings rule).

Allowlist is also user-extendable via `scrubber.allowlist_patterns`. Provider-key shapes and private-key headers are **never** allowlisted — no false-positive pressure there justifies the risk.

### 11.2 Behavior

- **`remember` (single):** on match, exits non-zero with the matched pattern name and a masked snippet. `--force-insecure` bypasses; the write is tagged `source='forced-insecure'` in events for auditability.
- **`remember-batch`:** scrubs every entry up front, **rejects the whole batch on any hit**, and writes a structured per-entry report to stderr so the agent can recover without re-submitting blind. Output is JSON when `--format json` is passed (default for batch), text otherwise. Example (one clean entry, one rejected):

    ```json
    {
      "ok": false,
      "scanned": 12,
      "clean": 11,
      "rejected": 1,
      "hits": [
        {
          "index": 4,
          "key": "task:2026-04-20-slack-webhook",
          "pattern": "provider_key.slack_bot",
          "field": "summary",
          "offset": 182,
          "snippet": "...token is `xoxb-****************************************7a2c`..."
        }
      ]
    }
    ```

    Exit codes: `0` clean, `2` any hit (distinct from generic errors at `1`). Agents are expected to drop the offending entries (`.hits[].index`) from the batch and retry; anamnesis does not auto-retry because the agent owns the summary content.

- **Bypass modes.** `--force-insecure` forces the entire batch through with every write tagged `source='forced-insecure'`. `--force-insecure-indices 4,9` forces only the listed entries — the agent can opt in per-entry when it genuinely needs to commit a high-entropy string it knows isn't secret (e.g. a documented test fixture). Both modes produce one `events` row per forced write and surface in `anamnesis audit --source forced-insecure`.
- **`anamnesis scrub`:** standalone, reads stdin, reports findings, exits 0 if clean, 2 on hit. The skill instructs the agent to self-check via `scrub` before calling `remember`.
- **Order of operations:** scrub first, then embed, then insert. Scrub rejections never incur embedder cost.
- **`anamnesis doctor --scan-existing-for-secrets`:** re-runs scrubber over existing entries after a pattern-list upgrade. Reports hits; does not auto-delete.

### 11.3 Skill guidance

*"Summaries describe structure, not literal values. Never paste token bodies, API keys, cookie contents, or database rows verbatim. Refer to shape: 'refresh token format is v2-prefix + uuid + 64-hex MAC' — do not include an actual token."*

Belt-and-suspenders: the agent learns the pattern, the CLI enforces it.

---

## 12. Schema Migrations

Anamnesis evolves. Safe migrations auto-apply on next CLI invocation. Destructive ones require explicit user action.

### 12.1 Flagging

Migration files embedded via `go:embed`. Each pair (`NNNN_description.up.sql` / `.down.sql`) declares its kind via a header comment:

```sql
-- anamnesis:migration safe
ALTER TABLE entries ADD COLUMN pinned BOOLEAN NOT NULL DEFAULT FALSE;
```

```sql
-- anamnesis:migration destructive
-- anamnesis:description Changes embedding vector dim from 1024 to 1536. Re-embedding required.
DROP INDEX idx_entries_embedding;
ALTER TABLE entries ALTER COLUMN embedding TYPE vector(1536) USING NULL;
```

### 12.2 Apply path

- **Safe:** on every CLI startup, check schema version. If only safe migrations pending, take `pg_advisory_lock(hashtext('anamnesis-migrate'))`, apply them, log a stderr line, proceed.
- **Destructive:** abort on startup with a clear message including the migration description. Require `anamnesis migrate --apply-destructive` followed by TTY y/N confirmation. First destructive upgrade also requires a one-time `--i-have-a-backup` assertion, persisted in global config so subsequent upgrades don't re-prompt.
- **Dry-run:** `anamnesis migrate --dry-run` prints pending migrations with their headers. No writes.

### 12.3 Rollback

No sanctioned downgrade path. Down-migrations exist for development/review hygiene but require `anamnesis migrate --to N --i-know-what-im-doing` and are documented as break-glass. The supported rollback procedure is: restore a pre-upgrade backup with the prior binary version.

### 12.4 Extensions

`anamnesis migrate` does not install Postgres extensions unless `--install-extensions` is passed and the role has permission. If an extension is missing, the migrate step prints the exact `CREATE EXTENSION` SQL the user must run (or their DBA must run).

---

## 13. Embeddings: Bundled Default, API Opt-In, Migration

### 13.1 Default: bundled local model

Anamnesis ships with **EmbeddingGemma-300M** (Google DeepMind, Sept 2025) embedded in the binary. It is the best-in-class small embedding model as of April 2026 — **#1 on MTEB code retrieval under 500M parameters (68.76)**, with built-in task-prompt support for code-vs-general queries and Matryoshka Representation Learning that produces usable embeddings at 768, 512, 256, or 128 dimensions from one set of weights.

| Property | Value |
|----------|-------|
| Model | `onnx-community/embeddinggemma-300m-ONNX`, INT8 quantization |
| Parameters | 308M |
| Native dimension | 768 (Matryoshka-truncatable to 512 / 256 / 128) |
| Default dimension in anamnesis | **512** |
| Context | 2048 tokens (plenty for 100–500 token summaries) |
| Languages | 100+ |
| License | Gemma Terms of Use (commercial-friendly; use-based restrictions; must propagate terms on redistribution) |
| Disk size (bundled, INT8) | ~300 MB |
| Inference latency (CPU) | 15–30 ms per embed on Apple Silicon, 20–50 ms on x86 |
| Runtime | ONNX via `yalue/onnxruntime_go` (CGo; already present for tree-sitter) |
| Runtime memory | ~200 MB resident while loaded; only loaded for operations that embed |

**What this means in practice:**
- `anamnesis init` enables semantic recall with zero configuration. No API keys, no network.
- Total anamnesis binary grows from ~80 MB (tree-sitter only) to ~380 MB (with model + ONNX runtime). Acceptable for a developer tool.
- Code-aware prompt templating (§6.1) is applied automatically — callers never think about it.
- Quality is ~80% of the best API models on retrieval benchmarks. For domain-narrow code memory the gap is smaller.

**Model weights** are embedded via `go:embed` for INT8. The INT4 quantization is available as an optional thin-install variant (`anamnesis install --embedding-quant int4`, ~150 MB, slight quality trade).

### 13.2 Opt-in API providers

Users who want higher-quality vectors or specialized models can switch:

```bash
anamnesis re-embed --provider voyage --model voyage-3-large [--dim 2048] [--dry-run]
anamnesis re-embed --provider openai --model text-embedding-3-large [--dim 3072]
anamnesis re-embed --provider cohere --model embed-v4
anamnesis re-embed --provider ollama --model nomic-embed-text [--base-url http://localhost:11434]
anamnesis re-embed --provider openai-compatible --model <X> --base-url <URL>

# Switch back to bundled local at any time:
anamnesis re-embed --provider local
```

Providers built into v1: `local` (default), `voyage`, `openai`, `cohere`, `ollama`, `openai-compatible`. No plugin loading; add a provider in v1.x if a meaningfully different SDK shape emerges.

### 13.3 When `re-embed` is needed

You change **provider**, **model**, or **dimension**. Vectors from different models don't share a vector space; switching requires regenerating every row.

### 13.4 `re-embed` phases

1. **Validate:** provider reachable (for API providers), a test embed returns the expected dim.
2. **Plan:** count rows needing re-embed (`WHERE embedding_model IS DISTINCT FROM $new_model_tag`). For API providers, estimate cost from a pricing table shipped with the binary. Estimate wall-clock from observed per-batch latency.
3. **Dry-run mode:** print the plan and exit.
4. **Confirm:** if dim differs, TTY prompt summarizing the change and asserting a recommended backup. Require explicit y.
5. **Lock:** `pg_advisory_lock(hashtext('reembed'))`. Concurrent re-embed exits cleanly.
6. **Dim change (if applicable):** `DROP INDEX idx_entries_embedding; ALTER TABLE entries ALTER COLUMN embedding TYPE vector(N_new) USING NULL;` — one transaction.
7. **Batch loop:** fetch stale rows, embed via new provider, update each row with vector + `embedding_model` + `embedding_generated_at`. Commit per batch.
8. **Resume:** progress persists per-batch. Re-running `re-embed` picks up where it left off — same filter, idempotent.
9. **Finalize:** `CREATE INDEX idx_entries_embedding USING hnsw(...)`. Minutes on big stores; progress reported.
10. **Update config:** write new `embedding.provider`, `embedding.model`, `embedding.dimension` to `~/.anamnesis/config.yaml`.

### 13.5 During migration

Recall's vector branch filters on both `embedding IS NOT NULL` **and** `embedding_model = <current-config-tag>`. This covers two cases cleanly:

- **Dim change.** Step 6 of §13.4 nulls every vector before the batch loop repopulates; rows drop from `sm` until re-embedded. Until the HNSW index is recreated in step 9, the `sm` CTE falls back to a sequential scan — fine for a few thousand rows, slow on a 100k-entry store. `anamnesis stats` surfaces *"index rebuilding"* so the user knows why recall feels heavier.
- **Same-dim, different-model switch.** Old vectors remain in place, but their `embedding_model` tag still points at the previous provider/model, so the tag filter excludes them from `sm` until the batch loop overwrites with the new provider's vector. This prevents the silent-corruption case where two different vector spaces coexist in one HNSW index.

`anamnesis stats` reports progress: *"re-embed in progress: 23,416 / 47,312 entries (49%) — model `voyage-3-large@512`"*.

### 13.6 New writes during migration

Every `remember` call embeds with the **currently-configured** provider/model — new writes land already on the new model. Re-embed only backfills old rows.

### 13.7 Model tag format

`embedding_model` column stores a stable tag combining model name and dimension, e.g. `embeddinggemma-300m@512`, `voyage-3-large@2048`, `text-embedding-3-large@3072`. This lets anamnesis distinguish "same provider, different dim" as a migration-worthy state change.

### 13.8 Cluster-wide dimension limitation

Dimensions remain **cluster-wide** in v1 — all projects on a given anamnesis install share one dim. Users who need mixed dims across projects run two anamnesis installs against two Postgres databases and point via `ANAMNESIS_DATABASE_URL`. Per-project dims are a v2 candidate if demand appears.

---

## 14. Backup & Restore

The store grows in value over months; a careless restore wrecks that. Anamnesis bakes in a restore path robust enough to survive AGE version mismatches and partial corruption by **rebuilding the graph from source** rather than trying to restore AGE's internal schemas.

### 14.1 `anamnesis backup`

```bash
anamnesis backup [--project NAME] [--all-projects] [-o FILE] [--no-embeddings]
```

Produces a single `.tar.gz` containing:

- **`manifest.json`:** schema version, anamnesis version, source project(s), embedding model + dim, timestamp, git commit SHA of the repo at backup time.
- **`entries.sql`:** `pg_dump -F p --data-only` filtered to target project(s). Plain SQL — inspectable with `tar tzf | less`, survives Postgres major-version changes.
- **`schema.sql`:** current DDL for reproducibility across anamnesis versions.

**Does not include the AGE graph.** It's reconstructible from source; shipping it invites AGE restore flakiness. Default includes embeddings (expensive to regenerate); `--no-embeddings` shrinks the file for users willing to re-embed on restore.

Default output path: `./anamnesis-<project>-<YYYYMMDD-HHMMSS>.tar.gz`. Stdout when `-` is passed (pipe-friendly).

### 14.2 `anamnesis restore`

```bash
anamnesis restore <file> [--project NAME] [--overwrite] [--skip-graph] [--verify]
```

1. Validate manifest. Refuse on incompatible schema version (tell user to run an older anamnesis to migrate the dump first).
2. Inserts projects + entries rows. Conflicts require `--overwrite` + TTY confirmation.
3. **Rebuilds the graph** via Phase 1 static analysis against `repo_root` on disk. Progress bar. Skippable with `--skip-graph` if the repo isn't present (user will run `anamnesis scan` later).
4. `--verify` cross-checks each restored entry's `content_hash` against the current on-disk git blob. Reports drift (entries whose source files have changed since backup).

### 14.3 `anamnesis export` vs `backup`

- **`backup`:** restore target. Plain SQL in tarball. For disaster recovery.
- **`export --format json`:** portability format. No schema leakage, consumable by non-Postgres tools, filterable. For inspection, sharing a subset, external analysis.

### 14.4 Scheduling

No scheduled backups in v1. The sanctioned recipe is in the manual:
- macOS: launchd plist template shipped alongside the binary.
- Linux: systemd timer template.
- Backup is pipe-friendly — plugs into rclone, S3, or any remote sink.

Scheduled backups as a first-class feature are v2.

---

## 15. Observability

Every CLI operation produces an event row (async, best-effort — observability must not introduce new failure modes). Queryable via `anamnesis audit`.

### 15.1 Source tagging

The skill sets `ANAMNESIS_SOURCE=agent:claude-code` (and equivalents for codex/aider). Git hooks set `ANAMNESIS_SOURCE=hook:post-commit`. Session continuity tracked via `ANAMNESIS_SESSION_ID`. Unset defaults to `cli`.

### 15.2 `anamnesis audit`

```bash
anamnesis audit [--today|--since DUR] [--project N] [--op recall|remember|...]
                [--key X] [--source agent:claude-code] [--outcome error]
                [--limit 100] [--format text|json]
```

Example output:

```
2026-04-16 09:14  recall       [0.12s]  q="session cookie"     → 3 results
2026-04-16 09:15  deps/impact  [0.04s]  src/lib/jwt.ts          → 7 files
2026-04-16 09:33  remember     [0.31s]  code:src/auth/verify.ts
2026-04-16 09:34  remember     [0.28s]  task:2026-04-16-extract-verify
```

### 15.3 Writes are async

Background goroutine. If the write fails (Postgres down), the primary op still reports success; dropped events log at debug. Per-event row rather than batch-aggregated so `audit --key <X>` always finds the operation.

### 15.4 Query scrubbing

Recall's `query` column runs through the scrubber before write (§11) — pasted tokens never land in the events table.

### 15.5 Stats integration

`anamnesis stats` pulls aggregate counts from events (recalls/remembers/scans per day, median latency, error rate). Single source of truth for tool usage.

### 15.6 Foundation for later

The events table enables v1.1 features like `anamnesis audit --agent-drift` (compare recall calls vs subsequent file reads to detect when the skill is being ignored). Not v1 work; free once the table exists.

---

## 16. Pruning

Three tiers, increasing in consent requirements.

### 16.1 Tier 1 — auto, no prompt

`anamnesis prune` (no args) runs:

- Tombstones (soft-deleted entries) past TTL (default 90d): hard-delete.
- Events past TTL (default 90d): hard-delete.

These are garbage — the user already consented by deleting / by not caring about ancient audit rows.

### 16.2 Tier 2 — confirm required

`anamnesis prune --orphans` — entries whose `file_paths[0]` no longer exists on disk, past a 30d grace period (gives rename detection a chance to resolve). Dry-run by default. Requires `--confirm` or TTY y/N. `anamnesis doctor --orphans` surfaces the same list as a diagnostic.

### 16.3 Tier 3 — explicit age-based

`anamnesis prune --older-than 180d` — entries with `updated_at` beyond the threshold.

**Excluded by default:**
- `task:` entries (timeless value; use `--include-tasks` to opt in).
- `conv:` entries (conventions don't go stale via neglect; use `--include-conv` to opt in).
- `pinned=true` entries (always excluded, no override).

Dry-run by default. Prints full list grouped by category. Requires `--confirm` to execute.

### 16.4 Never-prune

- **Stale entries** (`needs_refresh=true`) are never auto-pruned. Stale means the summary is probably wrong, not that it should be deleted — a flawed summary still has value; destroying it loses that value.
- Pinned entries are never pruned by any tier.

### 16.5 Trigger

User-invoked only. No background daemon. `doctor` output nudges the user (*"14 orphans past grace period — run `anamnesis prune --orphans`"*).

### 16.6 `--pin`

`anamnesis remember ... --pin` or `anamnesis pin <key>` sets `pinned=true`. Protects the most valuable hard-won entries from any future prune command. `anamnesis unpin <key>` reverses.

---

## 17. Concurrency Model

Single-dev doesn't mean single-process. Expect: Claude Code in one terminal, `git commit` firing the post-commit hook in another, maybe a background `scan --changed` from an editor integration, occasionally a second agent. Postgres handles most of this for free.

### 17.1 Principles

- **MVCC + UPSERT on rows.** Row-level races resolve correctly via `ON CONFLICT DO UPDATE`. No explicit locking on `remember`, `recall`, `forget`, `deps`.
- **Last-write-wins on entries.** Agent writes a fresh summary; hook's subsequent flag-set loses if the file hadn't actually changed (hash comparison proves it). If the file *did* change, flag-set is correct and the agent refreshes again. Worst case: one extra refresh cycle.
- **Hash recomputed on every write.** `remember` reads the current file, computes blob hash, stores with the entry. This is the primitive that makes last-write-wins safe.
- **Single-transaction graph edge rewrites.** `BEGIN; DELETE outgoing edges; INSERT new edges; COMMIT;`. Concurrent reads see either old or new — never partial.

### 17.2 Advisory locks (exclusive operations)

Operations that rewrite large swaths of state take `pg_advisory_lock(hashtext(<op>))`:

- `scan` (per project): `hashtext('scan:' || project)`
- `migrate`: `hashtext('anamnesis-migrate')`
- `re-embed`: `hashtext('reembed')`
- `prune`: `hashtext('prune:' || project)`
- `tags rename` / `tags merge`: `hashtext('tags:' || project)`

Second invocation exits cleanly with *"<op> already running for <project>"*. Released on connection close or explicit unlock.

### 17.3 Embedder concurrency

Client-side concern. Embedder module has a bounded worker pool (config: `embedding.workers`, default 4) and exponential-backoff retry on rate-limit errors. Not a PG concern.

### 17.4 Isolation level

Default `READ COMMITTED`. No need for stricter isolation except during migrations (which hold advisory lock anyway).

### 17.5 Connection pool

`pgxpool` with `MaxConns=10` per CLI invocation. Most commands use one or two connections briefly; the pool exists to avoid connect overhead on multi-query commands like `stats`.

---

## 18. Tag Taxonomy

Free-form tags with write-time normalization. No controlled vocabulary. Sprawl is handled after the fact with dedicated tooling.

### 18.1 Normalization

Applied at every write (`remember`, `remember-batch`, `remember-task`):

- Lowercase.
- Whitespace and underscore → `-`.
- Strip leading/trailing punctuation.
- Collapse repeated hyphens.
- Deduplicate within an entry's tag list.
- Reject empty tags, tags over 40 chars, tags with non-ASCII characters.

So `auth flow`, `Auth_Flow`, `auth-flow` all become `auth-flow`.

### 18.2 No controlled vocabulary

Agents invent new tags freely. Forcing a registry update before `remember` breaks the flow — the cost of sprawl is lower than the cost of friction.

### 18.3 Cleanup tooling

- `anamnesis tags` — list with entry counts and first/last-used dates. Sorted by count.
- `anamnesis tags rename <old> <new>` — bulk rewrite across all entries. Advisory lock, single transaction. One event per affected entry.
- `anamnesis tags merge <src>... <dst>` — sugar over rename for consolidating multiple strays.
- `anamnesis tags suggest` (v1.1) — clusters by edit distance + embedding similarity, suggests merge candidates.

### 18.4 Hierarchy

None in v1. Flat namespace. Users wanting hierarchy use kebab prefixes (`auth`, `auth-jwt`, `auth-session`) and query with `--tag-prefix auth` (not yet implemented but trivially addable).

### 18.5 Scope

Tags are per-project. The same tag string in two different projects is independent.

---

## 19. Configuration

### 19.1 Hierarchy

Three levels, later overriding earlier:

1. **`~/.anamnesis/config.yaml`** (global, `chmod 600`) — user-level defaults. **Secrets live here only.** API keys, default provider, default Postgres URL.
2. **`.anamnesis/project.yaml`** (per-project, **gitignored by default**) — project-specific overrides. Package glob map, `scan.exclude` additions, custom edge types. **Never secrets.**
3. **Env vars** — `ANAMNESIS_DATABASE_URL`, `ANAMNESIS_EMBEDDING_API_KEY`, `ANAMNESIS_PROVIDER`, `ANAMNESIS_SOURCE`, `ANAMNESIS_SESSION_ID`. Override both files.

`anamnesis config set embedding.api_key ...` always writes to the global file and chmods 600. CLI refuses to write secrets to project scope. `anamnesis init` auto-appends `.anamnesis/` to the project's `.gitignore`.

### 19.2 Example global config

```yaml
# ~/.anamnesis/config.yaml

database:
  url: "postgres://anamnesis:anamnesis_local@localhost:55432/anamnesis"
  pool_size: 10
  statement_timeout: 30s

embedding:
  provider: "local"              # local (default, bundled) | voyage | openai | cohere | ollama | openai-compatible
  model: "embeddinggemma-300m"   # for provider=local; ignored on the other providers
  dimension: 512                 # cluster-wide. Matryoshka-truncated from 768 for local.
                                 #   Change requires re-embed.
  quantization: "int8"           # local only: int8 (default, ~300 MB) | int4 (~150 MB, slight quality drop)
  # api_key_env: "VOYAGE_API_KEY"  # only needed when provider is an API provider
  batch_size: 32
  workers: 4
  timeout: 10s
  prompt_templates:              # applied transparently by anamnesis; override if you opted into a provider that handles prefixes differently
    code_document: "task: code retrieval | document: "
    code_query:    "task: code retrieval | query: "
    text_document: "task: search result | document: "
    text_query:    "task: search result | query: "

search:
  default_limit: 10
  trigram_threshold: 0.3
  vector_threshold: 0.3
  rrf_k: 60

graph:
  default_depth: 2
  max_depth: 8
  impact_depth: 4
  neighbourhood_hops: 2
  languages: [typescript, go, java, dart]

updates:
  git_hooks_default: true
  claude_code_hooks_default: false     # opt-in via install-hooks
  max_diff_tokens: 2000

scrubber:
  extra_patterns: []                    # project can add more
  allowlist_patterns: []                # skip matches for this shape (e.g. project-specific non-secret IDs)

prune:
  tombstone_ttl: 90d
  event_ttl: 90d
  orphan_grace: 30d

audit:
  retention: 90d
```

### 19.3 Example per-project config

```yaml
# .anamnesis/project.yaml  (gitignored by default)

name: "acme-monorepo"
repo_root: "/Users/alice/devel/acme"

scan:
  exclude:
    - "packages/legacy/**"
    - "**/*.generated.dart"

package_globs:                           # derive entries.package from path
  "packages/user-service/**": "user-service"
  "packages/billing/**": "billing"
  "apps/mobile/**": "mobile"
  "apps/web/**": "web"

graph:
  custom_edge_types: []                  # project-specific edge types (future)
```

---

## 20. Graceful Degradation

| Failure | Impact | Behaviour |
|---------|--------|-----------|
| Postgres unreachable | No memory or graph | CLI exits nonzero with a clear message. Agent falls back to file reads. |
| Bundled local model fails to load | No semantic search | ONNX runtime or model file error surfaced. Recall uses tsvector + pg_trgm only. `anamnesis doctor` diagnoses. |
| API embedding provider unreachable (opt-in case) | No semantic search | Recall uses tsvector + pg_trgm only. Warning logged. No auto-fallback to bundled model — vector space would differ. |
| pgvector extension missing | No vector index | `doctor` diagnoses. Recall degrades to keyword + fuzzy. |
| AGE extension missing | No graph queries | `deps` errors with remediation. Entries still work. |
| Embedding dim mid-migration | Reduced semantic quality | Vector branch filters `IS NOT NULL`; RRF continues. `stats` shows progress. |
| Empty store (pre-scan) | Nothing to recall | Agent proceeds with normal file reads. `recall` returns empty. |
| Post-commit hook fails | Slightly stale graph / flag | Non-fatal. Next commit or `anamnesis scan --changed` corrects. |
| Scan fails mid-way | Partial index | Already-written entries and graph nodes are kept. `scan --resume` continues. |
| Agent skips `remember` | Lost task insight | Best-effort. Skill prompt reminds; optional `Stop` hook nags more loudly. |
| Event write fails | Missing audit row for that op | Non-fatal; logged at debug level. Primary op reports success. |
| Scrubber false-positive | Legit write blocked | `--force-insecure` bypasses with audit record. Pattern fix in next release. |
| `ANAMNESIS_ENABLED=false` | Disabled entirely | `recall`/`deps` return empty, `remember` no-ops, agent works normally. |

---

## 21. Non-Goals

- **Not a completion-LLM orchestration tool.** Anamnesis owns embeddings (bundled local by default, API providers opt-in) as a pragmatic exception; all summary drafting is the agent's.
- **Not a chat-history store.** Conversations belong in the agent's history. Anamnesis stores *project knowledge*, not *session state*.
- **Not a firehose into agent context.** Memory is queried through a structured CLI. The agent decides what to recall.
- **Not a replacement for reading code.** Memory is a summary. When the agent needs exact current content, it still opens the file. Anamnesis tells it *which* file.
- **Not a style / policy enforcer.** `conv:` entries describe conventions; anamnesis does not lint or reject code.
- **Not team-shared in v1.** Multi-developer workflows, shared Postgres with ACLs, collaborative task entries — all v2.
- **Not an MCP server in v1.** CLI is the canonical contract. MCP layer is v1.x.
- **No scheduled background jobs in v1** (backups, prunes, re-embeds are user-invoked). Daemon-style automation is v2.

---

## 22. v1 Scope & Roadmap

### v1 ships

- Go binary (macOS arm64/amd64, Linux amd64/arm64), Docker Compose for Postgres 17 + pgvector + pg_trgm + AGE on port 55432, plus an opt-in Apache AGE Viewer service for graph visualisation.
- CLI: `recall`, `remember`, `remember-batch`, `remember-task`, `forget`, `mark-stale`, `deps`, `scrub`, `today`, `status`.
- Operator CLI: `server`, `init`, `scan`, `doctor`, `stats`, `audit`, `tags` (list/rename/merge), `migrate`, `re-embed`, `export`, `import`, `backup`, `restore`, `prune`, `install-skill`, `install-hooks`, `config`.
- Tree-sitter analyzers: TypeScript/JavaScript, Go, Java, Dart (Flutter).
- **Bundled local embedder: EmbeddingGemma-300M (INT8 ONNX), 512-dim via Matryoshka truncation, code-aware prompt templating, zero API keys required.**
- **Opt-in API providers: `voyage`, `openai`, `cohere`, `ollama`, `openai-compatible` — user-configured via `config set embedding.provider ...` + `anamnesis re-embed`.**
- Hybrid recall (tsvector + pg_trgm + pgvector with RRF fusion) — semantic recall works out of the box.
- AGE graph: `Module` nodes, 10 edge types including Flutter `RENDERS`.
- Content-hash staleness via git-blob-hash.
- Rename-aware post-commit hook (graph update + staleness flag).
- Optional Claude Code `PostToolUse` graph-refresh hook.
- High-entropy secret scrubber with hard-block on write.
- Events table + `audit` command.
- Soft-delete + three-tier prune.
- Cluster-wide embedding dim + explicit resumable `re-embed` (used for switching between local and API providers).
- Schema migrations (implicit-safe, explicit-destructive).
- Backup (plain SQL tarball) + graph-rebuild restore.
- Claude Code SKILL.md + Codex/Aider protocol snippets.
- `THIRD_PARTY_LICENSES.txt` in release artifacts covering Gemma Terms of Use (for EmbeddingGemma), tree-sitter grammars, ONNX runtime, and Go dependencies.

### v1.1 (next)

- Python and Rust analyzers.
- `anamnesis tags suggest` (sprawl detection via edit distance + embedding similarity).
- `anamnesis audit --agent-drift` (detect when the skill is being bypassed).
- MCP server (generated from cobra tree).
- Per-tag-prefix recall filter.

### v2 (strategic)

- Team-shared Postgres with project-level ACLs.
- Scheduled background maintenance (backups, prunes, opportunistic re-embeds).
- Per-project embedding dimension (if demand).
- Cross-project graph queries.
- Hosted cloud option.

### Unresolved, deferred

- Exact provider-pricing tables (updated per release; mechanism is plumbed, values are a release-time concern).
- HNSW parameter tuning guide for stores beyond 100k entries.
- Tree-sitter-dart grammar stability monitoring (community-maintained).
- Tag-prefix recall query syntax.
- Privacy of task entries in eventual team mode.
- EmbeddingGemma successor model (if Google releases one) — switch is a one-line config change + `re-embed`.
- GPU acceleration for the bundled embedder on supported hardware (Metal / CUDA via ONNX runtime providers). v1 is CPU-only; latency is already good.

---

## 23. Name

*Anamnesis* is the Platonic doctrine that learning is recollecting what the soul already knew. The name fits a tool whose job is to let an agent remember, across sessions and across the lifespan of a large codebase, what a past version of itself already figured out.
