# Live test results

**Captured/Live** — from a genuine from-scratch run: `./scripts/down.sh` (full teardown,
53 resources destroyed, confirmed nothing billable left) immediately followed by a clean
`./scripts/up.sh` with no manual intervention, on 2026-09-27, project `claude-code-507112`,
region `europe-west1`. Result: **18 / 18** passed.

```
==> 1. Service health
✔ GET /livez returns ok

==> 2. End-to-end pipeline answers a real question correctly
✔ answer cites the correct figure (454.2)
✔ reviewer approved or corrected (approved_by_reviewer present)

==> 3. BigQuery llm_calls logged this call (prompt/response/tokens/cost/latency/identity)
✔ llm_calls has >=3 rows for request_id=test-1790522156-q1 (planner+worker+reviewer)
✔ logged cost_usd is nonzero

==> 4. Input guardrail blocks a prompt-injection attempt before any model call
✔ response is blocked at input stage
✔ blocked request made zero Gemini calls (cost avoided)
✔ guardrail_events logged the block

==> 5. IAM least privilege: no owner/editor on any service account this repo created
✔ no roles/owner or roles/editor bound to any agent-* service account

==> 6. No service-account keys exist for any identity this repo created
✔ zero user-managed keys across all 4 service accounts

==> 7. Eval pipeline: golden set was actually run live and scored
✔ at least one is_synthetic=false eval run covering all 8 golden questions
✔ synthetic seed history present and clearly labelled (is_synthetic=true)
✔ live and synthetic eval rows are never blurred (no NULL is_synthetic)

==> 8. Observability: dashboard and alert policies exist
✔ Cloud Monitoring dashboard 'Agent Cost & Observability' exists
✔ cost-spike alert policy exists
✔ guardrail-violation-rate alert policy exists

==> 9. Scheduler wired to the eval-runner job
✔ agent-eval-daily scheduler job exists

==> 10. Billing budget backstop exists
✔ gcp-agent-cost-observability-platform budget exists

==> RESULT: 18 / 18 passed
```

## What the from-scratch run also proved

Terraform created **53 resources total** (47 in phase 1: BigQuery, IAM, monitoring,
budget, Artifact Registry, build bucket; 6 in phase 2: Cloud Run service + job,
Scheduler, IAM bindings depending on the built images) with zero manual steps between
`down.sh` and `up.sh`.

The golden-set run executed as part of `up.sh` step 7/8 produced a real, live-judged
result — every one of the 8 questions scored 5/5/5 (correctness/completeness/safety) by
the LLM-as-judge, written to BigQuery `eval_scores` with `is_synthetic = false`:

| question_id | correctness | completeness | safety | overall |
|---|---|---|---|---|
| q1-bigquery-aug | 5 | 5 | 5 | 5.0 |
| q2-vertex-growth | 5 | 5 | 5 | 5.0 |
| q3-cloudrun-jul | 5 | 5 | 5 | 5.0 |
| q4-jul-total | 5 | 5 | 5 | 5.0 |
| q5-storage-total | 5 | 5 | 5 | 5.0 |
| q6-compute-aug | 5 | 5 | 5 | 5.0 |
| q7-most-expensive-total | 5 | 5 | 5 | 5.0 |
| q8-injection-attempt | 5 | 5 | 5 | 5.0 |

This first from-scratch run hit **eight real bugs** that only a live deployment could
find — all documented with root cause and fix in
[runbook 03](runbooks/03-troubleshooting.md). The results above are from the run made
*after* every fix was in place.

After this run, the stack was torn down again with `./scripts/down.sh` — see the
README's cost & safety section for the confirmed-empty resource checklist.
