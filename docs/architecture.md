# Architecture

See the [diagram](img/architecture.svg) (source: [`docs/diagrams/architecture.py`](diagrams/architecture.py)).

## Request path (numbered 1-7 on the diagram)
1. An authenticated caller (the operator, or `agent-eval-runner`) POSTs `/ask` with a
   question, carrying a Google-minted ID token — the service has no `allUsers` binding.
2. The input guardrail (`app/pipeline/guardrails.py::check_input`) screens the question
   for known prompt-injection phrasings. A match short-circuits the request — no Gemini
   call is made, no cost is incurred, and a `guardrail_events` row is logged.
3. If not blocked, the **planner** agent calls Gemini to decide which 1-3
   `(service, month)` lookups the question needs.
4. The **worker** agent calls Gemini with the `query_spend` function declared as a tool;
   Gemini decides when and how to call it (real function calling, not a canned branch),
   the app executes `spend_data.query_spend(...)` against the in-process synthetic
   fixture, and feeds the result back for up to 3 round trips before drafting an answer.
5. Every one of these Gemini calls goes through `llm_client.call_gemini`, which logs
   prompt, response, input/output/thinking token counts, computed cost (published Vertex
   AI pricing), latency, and agent/step identity to BigQuery `llm_calls` — and emits a
   matching structured stdout log line that Cloud Monitoring's log-based metrics read.
6. The **reviewer** agent checks the worker's draft against the exact tool results (not
   by re-deriving the answer) and either approves it or corrects it. The final answer
   then passes the output guardrail (`check_output`): Vertex AI safety ratings plus an
   explicit secret-shaped-string check. A block here is logged the same way as an input
   block.
7. `llm_calls` and `guardrail_events` feed the Cloud Monitoring dashboard via log-based
   metrics extracted from the structured stdout the app emits.

## Evaluation path (numbered 8-10)
8. Cloud Scheduler (or a manual `gcloud run jobs execute`) starts the `agent-eval-runner`
   Cloud Run Job on an OAuth token scoped to exactly that job.
9. The job calls the **same deployed** `agent-pipeline` service, with its own ID token,
   for every question in the fixed golden set — exercising the real guardrails and
   logging path, not an in-process shortcut.
10. Each answer is scored 1-5 on correctness/completeness/safety by an LLM-as-judge
    Gemini call (`app/judge/judge.py`) against a reference answer computed from the same
    fixture data, and written to `eval_scores` with `is_synthetic = false`.

## Data
`app/pipeline/spend_data.py` is a small, deterministic (fixed-seed) synthetic cloud-spend
fixture — the only "dataset" the agent ever reasons over. It is never presented as real
billing data. See [ADR 0002](adr/0002-synthetic-seed-data-for-eval-history.md).

## Identities
Four service accounts, each scoped to exactly its job (`agent-pipeline`,
`agent-eval-runner`, `agent-scheduler`, `agent-build`) — see
[`terraform/identities.tf`](../terraform/identities.tf) and the
[threat model](threat-model.md) (T7, T9, T10).
