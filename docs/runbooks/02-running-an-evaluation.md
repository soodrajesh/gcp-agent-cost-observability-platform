# 02 — Running an evaluation

## On demand
```bash
gcloud run jobs execute agent-eval-runner --region europe-west1 --wait
```
This runs the fixed 8-question golden set (`golden_set/golden_set.json`) through the
**deployed** `agent-pipeline` service (real authenticated HTTPS calls, same guardrails
and logging path a real user would hit), scores each non-blocked answer with the
LLM-as-judge (`app/judge/judge.py`) against its reference answer, and writes one row per
question to `agent_observability.eval_scores` with `is_synthetic = false`.

## On schedule
Cloud Scheduler (`agent-eval-daily`, default `0 7 * * *` UTC) triggers the same Job
automatically. Change the cadence with `terraform apply -var schedule_cron="..."`.

## Inspecting results
```sql
SELECT run_id, question_id, correctness, completeness, safety, overall, judge_notes
FROM `<project>.agent_observability.eval_scores`
WHERE is_synthetic = false
ORDER BY scored_at DESC;
```
Trend over time (real runs only):
```sql
SELECT DATE(scored_at) AS day, AVG(overall) AS avg_overall
FROM `<project>.agent_observability.eval_scores`
WHERE is_synthetic = false
GROUP BY day ORDER BY day;
```
The Cloud Monitoring dashboard's "Eval score trend" panel charts the log-based metric
`agent_obs/eval_overall_score`, which every run — synthetic seed or live — feeds; filter
by `is_synthetic` in BigQuery when you need to separate the two for real analysis (see
[ADR 0002](../adr/0002-synthetic-seed-data-for-eval-history.md)).

## Editing the golden set
Edit `golden_set/golden_set.json`. Reference answers for the numeric questions were
computed directly from `app/pipeline/spend_data.py`'s deterministic fixture (fixed seed
= 42) — regenerate them with the snippets in that module's `query_spend` /
`total_by_service_across_months` / `growth_pct` helpers if you change the fixture.
