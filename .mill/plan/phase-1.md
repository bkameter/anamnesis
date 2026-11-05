# Phase 1 — Concept doc update

All edits land in `docs/concept.md`. One phase: the units are independent edits to one file, ordered so the final unit's sweep checks the whole AC set.

### Unit 1.1 — Bundled embedder name, tag, config, facts (AC #1)

**Test first:** `grep -n -i 'embeddinggemma-300m\|EmbeddingGemma-300M\|308M\|68\.76\|as of April 2026' docs/concept.md` — asserts no hits; fails now (intro l.9, §4.3 l.175/l.222, §6 l.352, §6.3 `$4` l.373, §13.1 l.781–792, §13.7 l.854, config l.1094, §22 l.1205).

**Corner cases:**
- §13.1 table: model id `onnx-community/embeddinggemma-2-ONNX` text tower, q8; disk size ~314 MB; context 8K; MTEB code 78.68; parameter count and native dim/latency/memory taken from the model card, not guessed — if the card lacks a figure, drop the claim rather than keep the 300M value.
- §4.3 dimension paragraph keeps default **512** (ticket Out: dimension unchanged); only re-word Matryoshka claim if the card's native dim differs from 768.
- Tag is exactly `embeddinggemma-2@512` and config exactly `model: "embeddinggemma-2"` (owner's answer in issue comments).
- §13.1 "what this means" binary-size line (~380 MB) recomputed against ~314 MB.
- Generic "EmbeddingGemma supports task-specific query prefixes" (l.356) stays valid wording — reword to "EmbeddingGemma 2" only.

**Then:** Replace each hit with the EmbeddingGemma 2 equivalent, re-verifying facts against the `onnx-community/embeddinggemma-2-ONNX` / Google model card.

**End state:** grep returns nothing; `grep -c 'embeddinggemma-2' docs/concept.md` ≥ 5; `cd app && go test ./...` passes.

### Unit 1.2 — Document prompt format (AC #2)

**Test first:** `grep -n '| document: ' docs/concept.md` — asserts no hits; fails now (§6.1 l.360–361, §19.2 l.1103/1105).

**Corner cases:**
- Query rows (`task: … | query: `) stay as-is unless the model card says otherwise (Carder note).
- `\|` escaping inside the §6.1 markdown table must be preserved so the table still renders.
- Title placeholder: use the format the model card shows (`title: none | text: ` when no title); for entries, state whether the entry key is used as the title — pick the card's recommendation, note it in one line.

**Then:** Rewrite the two document-side rows in §6.1 and `code_document` / `text_document` in §19.2 to `title: … | text: `.

**End state:** grep returns nothing; `grep -c 'title: .* | text: ' docs/concept.md` ≥ 4; tests pass.

### Unit 1.3 — License to Apache 2.0 (AC #3)

**Test first:** `grep -n -i 'gemma terms' docs/concept.md` — asserts no hits; fails now (§13.1 l.791, §22 l.1219).

**Corner cases:** none — two literal lines; the THIRD_PARTY_LICENSES line keeps its other items (tree-sitter, ONNX runtime, Go deps).

**Then:** §13.1 license row → `Apache 2.0`; §22 line → "covering Apache 2.0 (EmbeddingGemma 2), tree-sitter grammars, …".

**End state:** grep returns nothing; `grep -n 'Apache 2.0' docs/concept.md` hits both places; tests pass.

### Unit 1.4 — Current API model names (AC #4)

**Test first:** `grep -n 'voyage-3-large\|text-embedding-3-large\|embed-v4' docs/concept.md` — asserts no hits; fails now (§13.2 l.810–812, §13.5 l.846, §13.7 l.854).

**Corner cases:**
- Look names up in current Voyage / OpenAI / Cohere docs at implementation time (owner's answer); if a provider's current model is still the listed one, keep it and say so in the MR.
- `--dim` values in §13.2 and the `@<dim>` tags in §13.5/§13.7 must be dims the new models actually support.
- Ollama / `openai-compatible` lines use placeholders — leave untouched.

**Then:** Replace the model names (and dims where needed) consistently across §13.2, §13.5, §13.7.

**End state:** grep returns nothing; tests pass.

### Unit 1.5 — §22 roadmap: image embedding entry, drop successor line (AC #5)

**Test first:** `grep -n 'successor model' docs/concept.md` returns nothing **and** `grep -n -i 'vision encoder' docs/concept.md` hits §22; fails now (l.1244 present, no vision entry).

**Corner cases:**
- Entry goes under `### v1.1 (next)` or `### v2 (strategic)` — v2, since design is explicitly out of scope; one or two lines only, no design details (category, staleness, formats — ticket Out).
- Must mention the workaround: describe the diagram in an `arch:` entry with the image path in `file_paths`.

**Then:** Delete the successor line; add the roadmap bullet.

**End state:** both greps behave as stated; final sweep — re-run the Unit 1.1–1.5 greps together, all clean; tests pass.
