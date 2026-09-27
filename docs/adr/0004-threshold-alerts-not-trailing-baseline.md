# 0004 — Threshold alert policies, not a trailing z-score baseline

## Status
Accepted

## Context
This repo's sibling, `gcp-finops-cost-anomaly-detector`, detects cost anomalies with a
14-day trailing z-score baseline per (service, SKU, namespace). That approach needs
history: at least ~2 baseline windows of daily data before it can flag a deviation
meaningfully.

This repo's Cloud Monitoring alert policies (cost spike, guardrail-violation rate) are
created and exercised within a single build-test-teardown session — there is no 14-day
history of log-based-metric data to build a trailing baseline from, and one wouldn't
exist until this stack had been running continuously for weeks.

## Decision
Use simple threshold alert policies instead:
- **Cost spike**: alert if the p99 of logged per-call `cost_usd` over a 5-minute window
  exceeds `var.cost_alert_threshold_usd` (default $1 — deliberately low so the live test
  suite can prove the alert condition is real without needing a large synthetic spend
  burst). `cost_usd` is logged as a Cloud Monitoring `DISTRIBUTION` metric (GCP log-based
  metrics only support value extraction into `DISTRIBUTION`, not a plain `DOUBLE` gauge —
  found live on the first `terraform apply`, see
  [runbook 03](../runbooks/03-troubleshooting.md)), and a `DISTRIBUTION` can't be
  compared to a scalar threshold without a percentile aligner — `ALIGN_SUM` was rejected
  by the Monitoring API outright. p99-per-call is therefore a "did one call cost way more
  than expected" signal, not literally "total spend in the window".
- **Guardrail violation rate**: alert if the guardrail-block count is greater than zero
  in a 5-minute window (i.e., any block at all pages — appropriate for a demo-scale
  system where a single golden-set injection test is expected to fire it).

## Trade-off called out
A fixed threshold doesn't adapt to normal usage growth the way a trailing baseline does,
and the guardrail-violation policy in particular is deliberately oversensitive (alerts on
the very first violation) for demonstrability — a production deployment handling real
traffic would want a rate-based condition (violations per N requests) instead of an
absolute count, and would likely want the trailing-window anomaly approach from
`gcp-finops-cost-anomaly-detector` once enough history exists. This is a known gap,
documented rather than silently simplified.
