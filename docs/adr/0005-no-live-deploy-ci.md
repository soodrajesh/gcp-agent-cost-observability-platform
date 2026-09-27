# 0005 — CI is lint/validate/scan only; no live-deploy job

## Status
Accepted

## Context
Same reasoning as `gcp-finops-cost-anomaly-detector` ADR 0004. A GitHub-Actions job that
deployed or tested against the live GCP project would need Workload Identity Federation
(WIF) configured for this repo, credentials with real permissions on `claude-code-507112`,
and a running (billed) stack kept alive between CI runs — none of which this
single-developer portfolio project provisions.

## Decision
`.github/workflows/ci.yml` runs four jobs, all self-contained and free of GCP
credentials: `terraform fmt`/`validate`, a Trivy IaC misconfiguration scan, Python
lint + unit tests (`pricing.py`, `guardrails.py` — pure functions, no network), and a
shell lint/syntax check. The synthetic eval-history generator is smoke-tested for
determinism in CI, but nothing in CI calls Vertex AI, BigQuery, or Cloud Run.

## Trade-off called out
CI never proves the live stack still deploys or that `scripts/test.sh` still passes
against a real deployment — that verification only happens when a human runs
`./scripts/up.sh` and `./scripts/test.sh` themselves, as this repo's README states. A
team running this for real would add a WIF-authenticated `deploy` job gated behind manual
approval, provisioning and tearing down an ephemeral environment per run.
