-- Mounted by compose.yaml as /docker-entrypoint-initdb.d/00-extensions.sql
-- See docs/concept.md §4.2.

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS age;
