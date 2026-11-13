# Bundled embedder: EmbeddingGemma 2

Status: accepted
Ticket: #6

## Context
Issue #6 notes that Google released EmbeddingGemma 2 after the concept named EmbeddingGemma-300M. No embedder code existed yet, so this was a spec change only. See `19-embeddinggemma-300m.md` for the earlier choice.

## Decision
Name EmbeddingGemma 2 (text tower, q8 ONNX, ~314 MB, tag `embeddinggemma-2@512`) as the bundled default embedder.

## Rejected options
- **Keep EmbeddingGemma-300M**: Gemma Terms of Use instead of Apache 2.0, MTEB code 68.76 vs 78.68, and a 2K context vs 8K (issue #6 Problem).

## Consequences
- License note is Apache 2.0; the bundled size stays about the same.
- Default dimension stays 512.
- Image embedding via the vision encoder became a roadmap item, not part of this decision.
