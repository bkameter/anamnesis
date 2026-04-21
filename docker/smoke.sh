#!/usr/bin/env bash
# Smoke-test the anamnesis-db container.
# Run from repo root: bash docker/smoke.sh
# Exits 0 on success, non-zero on first failure.
set -euo pipefail

echo "==> Waiting for container to be healthy..."
for i in $(seq 1 24); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' "$(docker compose -f docker/compose.yaml ps -q anamnesis-db)" 2>/dev/null || true)
  if [ "$STATUS" = "healthy" ]; then break; fi
  echo "    ($i/24) status=$STATUS — sleeping 5s"
  sleep 5
done
if [ "$STATUS" != "healthy" ]; then
  echo "ERROR: container did not become healthy in 120s"
  docker compose -f docker/compose.yaml logs anamnesis-db
  exit 1
fi

DB_CONTAINER=$(docker compose -f docker/compose.yaml ps -q anamnesis-db)
PSQL="docker exec -i $DB_CONTAINER psql -U anamnesis -d anamnesis -v ON_ERROR_STOP=1 -t -A"

echo "==> AC1: extensions present"
EXTS=$($PSQL -c "SELECT extname FROM pg_extension WHERE extname IN ('pg_trgm','vector','age') ORDER BY extname;")
EXPECTED=$'age\npg_trgm\nvector'
if [ "$EXTS" != "$EXPECTED" ]; then
  echo "FAIL: expected 3 extensions, got:"
  echo "$EXTS"
  exit 1
fi
echo "    OK: $EXTS"

echo "==> AC2: pgvector — vector distance query"
NEAREST=$($PSQL -c "SELECT id FROM (VALUES (1,'[1,2,3]'::vector),(2,'[4,5,6]'::vector)) t(id,v) ORDER BY v <=> '[1,2,3]'::vector LIMIT 1;")
if [ "$NEAREST" != "1" ]; then
  echo "FAIL: expected id=1 nearest, got $NEAREST"
  exit 1
fi
echo "    OK: nearest id=$NEAREST"

echo "==> AC3: pg_trgm — similarity > 0"
SIM=$($PSQL -c "SELECT similarity('kitten', 'sitting') > 0;")
if [ "$SIM" != "t" ]; then
  echo "FAIL: similarity returned false"
  exit 1
fi
echo "    OK: similarity > 0"

echo "==> AC4: Apache AGE — create/query/drop graph"
$PSQL -c "
  LOAD 'age';
  SET search_path = ag_catalog, public;
  SELECT create_graph('smoke_test');
  SELECT * FROM cypher('smoke_test', \$\$ CREATE (a:Foo {k: 'v'}) RETURN a \$\$) AS (a agtype);
  SELECT drop_graph('smoke_test', true);
" > /dev/null
echo "    OK: AGE graph round-trip"

echo ""
echo "All smoke tests passed."
