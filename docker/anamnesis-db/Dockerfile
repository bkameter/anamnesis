# Postgres 17 + pgvector + pg_trgm + Apache AGE
# See docs/concept.md §4.2 for rationale. No upstream image bundles all three,
# so this image combines pgvector/pgvector:pg17 as the base and builds Apache
# AGE (release/PG17/1.5.0) on top. Published port: 55432 (set in compose.yaml).

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
