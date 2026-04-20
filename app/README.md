# app — Anamnesis Go application

The `anamnesis` CLI binary and its supporting packages live in this module.

Module path: `github.com/bkameter/anamnesis/app` — the `/app` suffix reflects the monorepo layout (Docker lives in a sibling folder, see [`../docker/`](../docker/)).

## Status

Empty skeleton. No Go source yet — the design is in [`../docs/concept.md`](../docs/concept.md).

## Commands

All Go commands must be run from **this directory**, not the repo root:

```bash
cd app
go build ./...
go test ./...
golangci-lint run ./...
```

## Intended layout (from the concept doc)

```
app/
├── go.mod
├── go.sum
├── cmd/
│   └── anamnesis/          # CLI entry point (cobra)
│       └── main.go
├── internal/
│   ├── db/                 # Postgres access, pgx/v5
│   ├── embed/              # bundled ONNX embedding model wrapper
│   ├── graph/              # Apache AGE (Cypher) client
│   ├── scan/               # static analysis + tree-sitter drivers
│   ├── scrub/              # secret scrubber
│   └── ...
└── migrations/             # golang-migrate SQL files (go:embed)
```

Populated incrementally by follow-up tickets.
