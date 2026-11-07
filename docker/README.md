# Docker — Anamnesis local stack

Self-contained Postgres 18 + pgvector + pg_trgm + Apache AGE image, plus the optional Apache AGE viewer.

See [`../docs/concept.md`](../docs/concept.md) §4.2 for the design rationale (why we build AGE on top of `pgvector/pgvector:0.8.2-pg18`, why port 55432, why the viewer is loopback-only).

## Layout

```
docker/
├── age-viewer/
│   └── Dockerfile       # node:22-alpine override of apache/age-viewer v1.0.0
│                        # (upstream is unmaintained; all releases use EOL Node 14)
├── anamnesis-db/
│   ├── Dockerfile       # pgvector base + Apache AGE 1.7.0 (tag PG18/v1.7.0-rc0)
│   └── init.sql         # CREATE EXTENSION for pg_trgm, vector, age
├── compose.yaml         # anamnesis-db + (opt-in) age-viewer services
└── README.md            # this file
```

### Why a local `age-viewer/Dockerfile`?

The upstream `apache/age-viewer` project has not released a new tag since v1.0.0 (December 2021) and all released tags use `node:14-alpine`, which reached EOL in April 2023. A transitive dependency (`minimatch@10.2.5`) requires Node 18/20/≥22, causing the upstream image build to fail.

`docker/age-viewer/Dockerfile` clones the upstream source at `v1.0.0` (verified against commit `2c55b23`) and builds it on a digest-pinned `node:22-alpine`, with three Node 22 compatibility fixes applied (OpenSSL legacy provider for the webpack 4 frontend build, `grep -E` instead of removed `egrep`, ESLint plugin disabled for the frontend build).

## Run

From the repo root:

```bash
# Database only.
docker compose -f docker/compose.yaml up -d

# Database plus AGE viewer (Cypher UI).
docker compose -f docker/compose.yaml --profile viewer up -d

# Tear everything down (stops every service regardless of profile).
docker compose -f docker/compose.yaml down

# Coming from the old PG 17 stack? Run `down -v` once; its data is not migrated.
```

## Connection details

| Purpose | Value |
|---|---|
| Published port (host) | `55432` |
| In-network port | `5432` |
| Database / user | `anamnesis` |
| Password | `anamnesis_local` (local-only default; override via env before running in shared environments) |
| Default URL | `postgres://anamnesis:anamnesis_local@localhost:55432/anamnesis` |

## AGE viewer

Enabled by the `viewer` compose profile. Bound to `127.0.0.1:8089` because the viewer has no app-level auth.

- URL: <http://localhost:8089>
- From inside the viewer, connect with:
  - Host: `anamnesis-db` (compose service name, **not** `localhost`)
  - Port: `5432` (in-network port)
  - Database / user / password: as above
  - Graph name: one graph per project, named `proj_<sanitised-project-name>`. Use the `anamnesis project list` CLI to enumerate.

## Smoke test

Verify all three extensions work against a running container:

```bash
bash docker/smoke.sh
```

The script waits for the container to report `healthy`, then runs four checks: extensions present, pgvector distance query, pg_trgm similarity, Apache AGE graph round-trip. Exits non-zero on first failure.

## Build baseline (first run, April 2026)

| Metric | Value |
|---|---|
| Docker version | 28.3.2 |
| Final image size | 154 MB |
| First-build duration | ~47 s (Apple M-series, warm network) |
| Apache AGE tag | `PG18/v1.7.0-rc0` (upstream's tag for the final AGE 1.7.0 PG18 release) |

## AGE viewer first-paint

After `docker compose -f docker/compose.yaml --profile viewer up -d`, open <http://localhost:8089>. You will see a connection form. Enter:
- Host: `anamnesis-db`, Port: `5432`
- Database: `anamnesis`, User: `anamnesis`, Password: `anamnesis_local`

The AGE viewer build (~1–2 min) runs only once; subsequent starts are instant.

## Using your own Postgres

If you already run Postgres with the three extensions, skip this stack entirely and point the CLI at it via `ANAMNESIS_DATABASE_URL`. The CLI will install the extensions if it has permission; otherwise it prints the exact SQL to run.
