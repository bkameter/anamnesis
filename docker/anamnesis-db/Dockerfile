# Postgres 18 + pgvector + pg_trgm + Apache AGE
# See docs/concept.md §4.2 for rationale. No upstream image bundles all three,
# so this image combines pgvector/pgvector:0.8.2-pg18 as the base and builds Apache
# AGE (PG18/v1.7.0-rc0) on top. Published port: 55432 (set in compose.yaml).

FROM pgvector/pgvector:0.8.2-pg18 AS base

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential git ca-certificates postgresql-server-dev-18 \
        libreadline-dev zlib1g-dev flex bison && \
    cd /tmp && \
    git clone --branch PG18/v1.7.0-rc0 --depth 1 https://github.com/apache/age.git && \
    cd age && make && make install && \
    cd / && rm -rf /tmp/age && \
    apt-get purge -y build-essential git postgresql-server-dev-18 \
        libreadline-dev zlib1g-dev flex bison && \
    apt-get autoremove -y && apt-get clean && \
    rm -rf /var/lib/apt/lists/*

RUN echo "shared_preload_libraries = 'age'" >> /usr/share/postgresql/postgresql.conf.sample

HEALTHCHECK --interval=5s --timeout=5s --start-period=30s --retries=6 \
    CMD pg_isready -U anamnesis -d anamnesis || exit 1
