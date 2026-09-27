# 0006 — Authenticated-only Cloud Run service; a Job (not a Function) for evaluation

## Status
Accepted

## Context
Two related infrastructure shape decisions:

1. Should `agent-pipeline` accept anonymous (`allUsers`) traffic, or require
   authentication?
2. Should the golden-set evaluation run as a Cloud Function, a second Cloud Run
   service, or a Cloud Run Job?

## Decision
- **No `allUsers` IAM binding on the pipeline service.** Only the `agent-eval-runner`
  service account and the human operator's own identity (`var.admin_email`) hold
  `roles/run.invoker`. Every call — from the eval runner, from `scripts/test.sh`, from a
  manual `curl` — carries a Google-minted ID token. This directly narrows the STRIDE
  Spoofing/Elevation-of-Privilege surface: an internet-exposed, unauthenticated LLM
  endpoint that itself calls a metered, billed API (Vertex AI) is a real cost/abuse risk
  this repo deliberately does not take on.
- **A Cloud Run Job, not a Function or a second Service, for evaluation.** The eval
  runner has no inbound traffic, runs on a schedule (or on demand), exits when done, and
  bills nothing between runs — the same reasoning as `gcp-finops-cost-anomaly-detector`
  ADR 0001. A Cloud Function would need its own HTTP trigger plumbing for no benefit; a
  second long-running Service would bill for idle capacity it doesn't need.

## Trade-off called out
Requiring authentication means this repo cannot be demoed with a bare `curl` from an
arbitrary machine — a demo user needs `gcloud auth print-identity-token` and IAM access
to the project, which is a slightly higher bar than a public URL. That bar is the point:
it's the same control a real agent-serving team would want in front of anything that
spends money per call.
