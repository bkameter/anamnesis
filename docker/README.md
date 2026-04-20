# Docker — Anamnesis local stack

Self-contained Postgres 17 + pgvector + pg_trgm + Apache AGE image, plus the optional Apache AGE viewer.

See [`../docs/concept.md`](../docs/concept.md) §4.2 for the design rationale (why we build AGE on top of `pgvector/pgvector:pg17`, why port 55432, why the viewer is loopback-only).

## Layout

```
docker/
├── anamnesis-db/
│   ├── Dockerfile       # pgvector base + Apache AGE 1.5.0 for PG17
│   └── init.sql         # CREATE EXTENSION for pg_trgm, vector, age
├── compose.yaml         # anamnesis-db + (opt-in) age-viewer services
└── README.md            # this file
```

## Run

From the repo root:

```bash
# Database only.
docker compose -f docker/compose.yaml up -d

# Database plus AGE viewer (Cypher UI).
docker compose -f docker/compose.yaml --profile viewer up -d

# Tear everything down (stops every service regardless of profile).
docker compose -f docker/compose.yaml down
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

## Using your own Postgres

If you already run Postgres with the three extensions, skip this stack entirely and point the CLI at it via `ANAMNESIS_DATABASE_URL`. The CLI will install the extensions if it has permission; otherwise it prints the exact SQL to run.
