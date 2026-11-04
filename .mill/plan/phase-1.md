# Phase 1 — Version bump

Every change for the ticket. Each unit is one commit, and the suite (`cd app && go test ./... && golangci-lint run ./...`) stays green after each one. For the DB units the real check is `docker/smoke.sh`.

### Unit 1.1 — DB image on PG 18 + pgvector 0.8.2 + AGE 1.7.0, compose volume on the PG 18 layout (AC #1)

**Test first:** `docker/smoke.sh` (unchanged; the Carder confirmed it has no hard-coded versions), plus a version probe:
```
docker compose -f docker/compose.yaml down -v
docker compose -f docker/compose.yaml build --no-cache --pull anamnesis-db
docker compose -f docker/compose.yaml up -d anamnesis-db && bash docker/smoke.sh
docker exec -i $(docker compose -f docker/compose.yaml ps -q anamnesis-db) psql -U anamnesis -d anamnesis -tAc \
  "SELECT current_setting('server_version_num')::int/10000, (SELECT string_agg(extname||'='||extversion, ',' ORDER BY extname) FROM pg_extension WHERE extname IN ('age','vector'))"
```
This asserts `18|age=1.7.0,vector=0.8.2`. It fails now because the probe returns `17|age=1.7.0,vector=<whatever pg17 ships>`.

**Corner cases:**
- The build must not depend on a warm cache, so run it with `--no-cache --pull` (AC #1 says "clean build cache").
- The image and the mount change in the same commit. A PG 18 image with the old `/var/lib/postgresql/data` mount refuses to start, so splitting them would leave a broken branch.
- An existing PG 17 volume must not be reused. `down -v` drops it. A leftover old volume mounted at `/var/lib/postgresql` only holds a stray `data/` dir, and PG 18 initialises fresh under `18/docker`.
- The `postgresql.conf.sample` path is still valid in PG 18 (see the research note in `plan.md`). Check it explicitly.

**Then:** In `docker/anamnesis-db/Dockerfile`:
- set the base to `pgvector/pgvector:0.8.2-pg18`
- change `postgresql-server-dev-17` to `-18` (both the install and the purge)
- clone `--branch PG18/v1.7.0-rc0`
- update the header comment

In `docker/compose.yaml`:
- change the image tag to `anamnesis/postgres:18`
- change the volume to `anamnesis_pgdata:/var/lib/postgresql`

Change nothing else.

**End state:** the loom's configured test command passes; the image builds from scratch and `docker/smoke.sh` passes on PG 18.

### Unit 1.2 — Verify data survives down/up (AC #2)

**Test first:** a manual check (no new file; smoke.sh stays a read-only health check):
```
C() { docker exec -i $(docker compose -f docker/compose.yaml ps -q anamnesis-db) psql -U anamnesis -d anamnesis -v ON_ERROR_STOP=1 -tAc "$1"; }
C "CREATE TABLE persist_check(v text); INSERT INTO persist_check VALUES ('ok');"
docker compose -f docker/compose.yaml down && docker compose -f docker/compose.yaml up -d anamnesis-db && bash docker/smoke.sh
C "SELECT v FROM persist_check;"   # expect: ok
C "DROP TABLE persist_check;"
docker volume inspect anamnesis_anamnesis_pgdata   # or the project-prefixed name; volume must exist
docker exec $(docker compose -f docker/compose.yaml ps -q anamnesis-db) ls /var/lib/postgresql/18/docker/PG_VERSION
```
Before Unit 1.1 this fails, because a PG 18 image would not start on the old mount. After 1.1 it should pass with no code change.

**Corner cases:**
- `down` must be run without `-v`, otherwise the check proves nothing.
- Confirm the data really lives in the named volume (`PG_VERSION` under `18/docker`) and not in an anonymous volume. The PG 18 image declares `VOLUME /var/lib/postgresql`, so a wrong mount would silently create an anonymous volume, and that volume is lost on `down`/`up`.

**Then:** no change expected. If the check fails, fix the mount in `compose.yaml` only. Record the result in the MR, not in a file.

**End state:** the loom's configured test command passes; data survives restart.

### Unit 1.3 — Go module targets Go 1.27 (AC #3)

**Test first:** `cd app && grep -qx 'go 1.27.0' go.mod && go build ./... && go test ./...`. This fails now because go.mod says `go 1.26.1`.

**Corner cases:**
- `toolchain` line: `go mod edit -go=1.27.0` may add or keep a `toolchain` directive. Keep go.mod to the single `go 1.27.0` line unless the Go tool requires a `toolchain` line.
- If the local toolchain is older than 1.27, it auto-downloads (`GOTOOLCHAIN=auto`). Do not set `GOTOOLCHAIN=local`.

**Then:** run `cd app && go mod edit -go=1.27.0`, then `go mod tidy`. go.sum should not change, because there are no deps.

**End state:** the loom's configured test command passes; `go build ./...` succeeds on Go 1.27.

### Unit 1.4 — Docs name the new versions (AC #4)

**Test first:**
```
! grep -nE 'Postgres(QL)? 17|pg17|PG17|postgres:17|server-dev-17|1\.5\.0|1\.26' docs/concept.md docker/README.md
```
The command must print nothing. It fails now on the lines found at plan time: concept.md §4.2 (lines 68, 80, 84, 88, 91, 94, 107), the roadmap line (1201), and docker/README.md lines 3, 5, 12 and 71.

**Corner cases:**
- The concept.md §4.2 embedded Dockerfile and compose snippets must match the real files from Unit 1.1: base tag, `server-dev-18`, the AGE tag, `anamnesis/postgres:18`, and the volume at `/var/lib/postgresql`.
- The docker/README.md AGE row: the old note "no stable PG17 release exists yet; `release/PG17/1.5.0` … never shipped" is now false. Replace it with a note that `PG18/v1.7.0-rc0` is upstream's tag for the final 1.7.0 release. See the open question on AC #4 below.
- The "Build baseline (first run, April 2026)" table: update the AGE tag. Image size and build time get refreshed only if the Spinner measured them in Unit 1.1. Otherwise leave them as they are, with their date.
- Add one line to docker/README.md telling anyone with an existing PG 17 volume to run `docker compose -f docker/compose.yaml down -v` once, because the old data dir is not migrated (migration is out of scope per the ticket).
- Section §13 (embedding names) and the age-viewer are out of scope. Do not touch them.

**Then:** change only the version strings, snippets and the AGE note above.

**Open question on AC #4:** AC #4 lists "1.7.0-rc0" as an outdated version. Upstream's only tag for the final AGE 1.7.0 PG18 release is `PG18/v1.7.0-rc0`, so the docs say "Apache AGE 1.7.0" and cite that tag once as the upstream name. If the reviewer wants no `-rc0` string at all, the fallback is to clone `release/PG18/1.7.0`, which is the same commit but a mutable branch.

**End state:** the loom's configured test command passes; the grep above prints nothing.
