# 0001 — gemini-2.5-flash on the global endpoint

## Status
Accepted

## Context
This GCP project (`claude-code-507112`) has been used across several prior sessions to
prototype Vertex AI usage. Earlier sessions found that not every model/endpoint
combination works reliably in this project — some regional endpoints and some model
versions returned quota or availability errors. `gemini-2.5-flash` on the `global`
endpoint was the one combination verified to work reliably in earlier sessions.

Before writing any pipeline code for this repo, that finding was re-checked live
(2026-09-27) with a direct `generateContent` REST call against
`projects/claude-code-507112/locations/global/publishers/google/models/gemini-2.5-flash`.
It returned a normal response with `usageMetadata` populated (prompt/candidates/thoughts
token counts), confirming the combination still works and that token accounting — which
the cost-logging middleware depends on — is available.

## Decision
Every Gemini call in this repo (planner, worker, reviewer, and the LLM judge) uses
`gemini-2.5-flash` on the `global` endpoint, via a single client constructed once in
`app/pipeline/llm_client.py`. There is no per-agent or per-task model selection.

## Trade-off called out
A single flash-tier model is cheaper and faster but has weaker reasoning than a pro-tier
model, which matters most for the reviewer's job of catching a subtly wrong number. The
mitigation is structural, not a bigger model: the reviewer is given the exact tool-call
results as ground truth and asked to check the draft's figures against them, not to
re-derive the answer itself — a comparison task flash handles reliably. The `global`
endpoint also means no explicit region pinning for inference traffic, which is a minor
data-residency trade-off acceptable for this portfolio project.
