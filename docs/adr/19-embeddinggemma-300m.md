# Bundled embedder: EmbeddingGemma-300M

Status: superseded by 6-embeddinggemma-2.md
Ticket: #19
Source: docs/concept.md §13.1 (as of 62b61ba^)

## Context
The original concept bundled a local embedding model so semantic recall works with no API key. §13.1 at `62b61ba^` chose EmbeddingGemma-300M (INT8 ONNX, 308M parameters, 2048-token context, Gemma Terms of Use) as the default. Ticket #6 later replaced it.

## Decision
Bundle EmbeddingGemma-300M in the binary as the default embedder, at 512 dimensions via Matryoshka truncation.

## Rejected options
- **An API model as the default**: the old §13.1 puts the bundled model at "~80% of the best API models on retrieval benchmarks"; it is accepted because it needs no key or network (the full rationale is in `19-local-embedder-default.md`).

## Consequences
- Model tag was `embeddinggemma-300m@512`, config `model: "embeddinggemma-300m"`.
- Binary grew to ~380 MB; redistribution had to propagate the Gemma Terms of Use.
- Replaced by EmbeddingGemma 2 in #6; changing the model requires `anamnesis re-embed`.
