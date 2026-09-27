# 04 — Cost

## What actually costs money
- **Vertex AI (Gemini) calls** — the only meaningful cost. Each `/ask` call makes 2-4
  Gemini calls (planner, 1-3 worker round trips, reviewer); each golden-set run adds one
  judge call per question. At `gemini-2.5-flash` published pricing ($0.30/1M input,
  $2.50/1M output tokens including thinking tokens) a full `up.sh` run (smoke test + one
  8-question golden-set run) is on the order of a few thousand tokens total —
  well under $0.05. See `app/pipeline/pricing.py` for the exact rates used.
- **Cloud Run** — the service scales to zero when idle; the job bills only while an
  execution runs (a few seconds per golden-set run).
- **BigQuery / Cloud Monitoring / Cloud Scheduler** — usage here is a rounding error
  against their free tiers at this scale.
- **Artifact Registry / the build bucket** — negligible storage for two small images.

## Guardrails on spend
- A Terraform-managed Billing Budget (`var.budget_amount`, default €15/month) with
  50/90/100% email alert thresholds — a backstop, not the primary control.
- The cost-spike Cloud Monitoring alert policy (ADR 0004) pages if summed logged
  `cost_usd` exceeds `var.cost_alert_threshold_usd` (default $1) in a 5-minute window —
  tuned low deliberately so it's provably wired up without needing a large spend burst.
- The worker's tool-call loop is hard-capped at 3 round trips per request.
- `scripts/down.sh` removes every billable resource this repo creates; run it once
  you're done evaluating.

## Verifying nothing is left running
```bash
./scripts/down.sh
```
prints a live count per resource category (Cloud Run service/job, Scheduler job,
BigQuery dataset, Artifact Registry repo, build bucket, service accounts, billing
budget) — every line should read 0 except the billing budget, which the script does not
delete (Terraform destroy removes it too; the 0 there confirms it as well).
