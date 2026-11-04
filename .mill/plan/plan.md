# Plan — #5: chore: upgrade stack to PostgreSQL 18, Apache AGE 1.7.0, pgvector 0.8.2, Go 1.27

Satisfies Carder acceptance criteria: AC #1–#4 (see the ticket's `## Refined by Carder` section; affected files per Carder's affected-files table).

## Phases

1. **Version bump** — DB image + compose volume (AC #1, #2), Go module (AC #3), docs (AC #4), as four commit-sized units. See `phase-1.md`.

One phase only: the units are small, independent version bumps. Only the image and the volume mount must change together. There is no Go code yet, so `go build`/`go test` are trivial, and the real check for the DB units is `docker/smoke.sh`.

## Research notes for the Spinner (checked 2026-11-04)

- **pgvector base image:** `pgvector/pgvector:0.8.2-pg18` exists on Docker Hub (as do `-bookworm`/`-trixie` variants). Use the plain tag. It pins pgvector exactly, which AC #1 needs.
- **AGE 1.7.0 for PG 18:** upstream publishes the GitHub release "Release v1.7.0 for PG18" (not a pre-release) under the tag **`PG18/v1.7.0-rc0`**. The tag is on the same commit (`806fa2e`) as the `release/PG18/1.7.0` branch. No tag without `-rc0` exists. Clone the tag: it is immutable, and branches can move. Note: AGE 1.8.0 for PG18 is out too, but the ticket pins 1.7.0, so 1.7.0 it is.
- **PG 18 data-directory layout:** the postgres 18 images set `PGDATA=/var/lib/postgresql/18/docker` and declare `VOLUME /var/lib/postgresql`. If a volume is mounted at `/var/lib/postgresql/data`, the entrypoint refuses to start. The fix is to mount the named volume at `/var/lib/postgresql`.
- **`postgresql.conf.sample`:** the Carder asked whether `/usr/share/postgresql/postgresql.conf.sample` still exists in PG 18. Check it in the built image: `docker run --rm anamnesis/postgres:18 ls -l /usr/share/postgresql/postgresql.conf.sample`. If it is missing, append to `/usr/share/postgresql/18/postgresql.conf.sample` instead. compose also passes `-c shared_preload_libraries=age`, so smoke would still pass either way. Do not let that hide a broken `RUN` line.
- **Local Go is 1.26.1.** With `go 1.27.0` in go.mod, the default `GOTOOLCHAIN=auto` downloads 1.27 automatically.
