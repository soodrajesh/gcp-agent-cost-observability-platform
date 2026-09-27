# 0002 — Synthetic seed data for eval-score history (and for the agent's task dataset)

## Status
Accepted

## Context
Two different things in this repo need data, and they must not be confused with each
other:

1. **The eval-score trend chart** is supposed to show quality over time. A single build
   session can only produce one or a handful of real, LLM-judged golden-set runs — not
   enough to show a trend on a dashboard.
2. **The agent's task itself** (answering questions about "cloud spend") needs some
   dataset to reason over. This repo is not wired to a real GCP Billing export; using one
   would also make the golden set's reference answers non-deterministic across reruns.

## Decision
- `app/pipeline/spend_data.py` generates a small, deterministic (fixed-seed), clearly
  documented **synthetic fixture** of cloud spend across 5 services and 3 months. It is
  never presented as real billing data anywhere in the docs or code comments.
- `seed/generate_synthetic_eval_history.py` generates 20 days of **synthetic**
  `eval_scores` rows (`is_synthetic = true`), loaded once by `scripts/up.sh` via `bq
  load`, purely so the trend chart has more than one point.
- Every row this build actually judges live — via `app/judge/run_golden_set.py` calling
  the deployed service — is written with `is_synthetic = false`. The two are never
  blurred: every query, the dashboard, and the README distinguish them, and
  `scripts/test.sh` explicitly asserts `is_synthetic` is never `NULL`.
- `llm_calls` and `guardrail_events` are **never** seeded — every row in those two
  tables comes from a real, billed Vertex AI call.

## Trade-off called out
The synthetic history's "trend" (a dip around day 8, recovering afterwards) is
illustrative, not evidence the pipeline actually regressed and recovered on those dates.
Anyone using this repo's dashboard to judge real quality trends must filter to
`is_synthetic = false` and let real `eval_scores` rows accumulate over subsequent
scheduled runs.
