# Local embedder by default, API providers opt-in

Status: accepted
Ticket: #19
Source: docs/concept.md §13.1

## Context
Semantic recall needs an embedding model. §2.2 and §13.1 require that `anamnesis init` works with zero configuration, with no API keys and no network.

## Decision
Anamnesis owns the embedder and bundles a local ONNX model, on by default. API providers (Voyage, OpenAI, Cohere, Ollama) are opt-in via config and `anamnesis re-embed` (§13.2).

## Rejected options
- **An API provider as the default**: needs API keys and network access (§2.2, §13.1); kept as an opt-in for users who want higher-quality vectors.

## Consequences
- The binary carries the model weights and ONNX runtime (~400 MB).
- Switching provider or dimension later needs an explicit `re-embed` (§13.3).
- Embedding is the one pragmatic exception to "no external model calls" (§21).
