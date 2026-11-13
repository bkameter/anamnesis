# Architecture Decision Records

Decisions recorded as ADRs, in filename order.

- [Dependency graph in Apache AGE inside Postgres](19-age-graph-in-postgres.md): Graph in Apache AGE inside Postgres, not Neo4j or recursive CTEs.
- [Concurrency: MVCC and UPSERT, no explicit locking](19-concurrency-mvcc-advisory-locks.md): MVCC and UPSERT with no explicit locking; READ COMMITTED.
- [Bundled embedder: EmbeddingGemma-300M](19-embeddinggemma-300m.md): Original bundled embedder. Superseded by 6-embeddinggemma-2.md.
- [Free-form tags, no controlled vocabulary](19-free-form-tags.md): Free-form tags instead of a controlled vocabulary.
- [Rebuild the graph from source on restore](19-graph-rebuild-on-restore.md): Restore rebuilds the graph from source rather than restoring AGE schemas.
- [Hybrid recall over three paths](19-hybrid-recall-rrf.md): Recall fuses tsvector, pg_trgm and pgvector with RRF.
- [Local embedder by default, API providers opt-in](19-local-embedder-default.md): Bundled local embedder by default, API providers opt-in.
- [Storage-only for completions](19-storage-only-completions.md): Anamnesis never calls a completion LLM.
- [Tree-sitter static analyzers for graph edges](19-tree-sitter-analyzers.md): Graph edges from tree-sitter analyzers, not regex or LLMs.
- [Bundled embedder: EmbeddingGemma 2](6-embeddinggemma-2.md): EmbeddingGemma 2 replaces EmbeddingGemma-300M as bundled embedder.
- [User-approved session summaries](7-session-summaries.md): Session summaries stored only after user approval.
- [Reserved `_global` memory space](8-global-memory-space.md): Reserved `_global` space for cross-project knowledge.
