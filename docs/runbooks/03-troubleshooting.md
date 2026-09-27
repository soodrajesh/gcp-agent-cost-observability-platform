# 03 — Troubleshooting

Real bugs a live deployment found, in the order they were hit building this repo. The
from-scratch run recorded in the README's status line was made **after** every fix below
was already in place.

## 1. Billing Budget: "requires a quota project"
`google_billing_budget` failed with `403 ... requires a quota project` even though
`billingbudgets.googleapis.com` was enabled. Terraform's Google provider was using
Application Default Credentials without a quota project set.
**Fix**: `gcloud auth application-default set-quota-project <project>` once, plus
`user_project_override = true` / `billing_project = var.project_id` in
`terraform/providers.tf` so it isn't a one-time local fix only.

## 2. Log-based metric: "Number of label descriptors must match number of label extractors"
`google_logging_metric` needs an explicit `labels { key = ... value_type = ... }` block
inside `metric_descriptor` for **every** key used in `label_extractors` — declaring
`label_extractors` alone isn't enough. **Fix**: add matching `labels` blocks (see
`terraform/monitoring.tf`).

## 3. Alert policy: DISTRIBUTION metric can't be compared to a scalar threshold
`ALIGN_SUM` on a `DISTRIBUTION`-typed log metric was rejected outright: *"a time series
of type DISTRIBUTION cannot be compared directly to a literal numeric threshold without
first converting to a scalar via an explicit aligner such as ALIGN_PERCENTILE_50/95/99"*.
Also: GCP log-based metrics only support `value_extractor` on `DISTRIBUTION`-typed
metrics — a plain `DOUBLE` gauge with a value extractor is rejected with *"A value
extractor can only be specified for a DISTRIBUTION value type"*. **Fix**: keep
`cost_usd`/`latency_ms`/`eval_overall_score` as `DISTRIBUTION` with `bucket_options`, and
use `ALIGN_PERCENTILE_99` (not `ALIGN_SUM`) in the cost-spike alert condition — see
[ADR 0004](../adr/0004-threshold-alerts-not-trailing-baseline.md) for what that means
semantically.

## 4. `/healthz` reserved by Google's front end — never reaches the container
Every request to `.../healthz` returned Google's generic branded 404 page (not this
app's own 404), **even through an authenticated `gcloud run services proxy` tunnel** —
proving it never reached the container (confirmed: no matching line in `gcloud run
services logs read` for those requests, while `/docs` and `/` on the same service logged
normally). Google's front end intercepts the exact path `/healthz` for its own
infrastructure health checks. **Fix**: renamed the app's liveness endpoint to `/livez`
everywhere (`app/pipeline/main.py`, `terraform/run.tf` startup probe, `scripts/test.sh`).

## 5. Vertex AI call: wrong API version, then wrong host
Two sequential bugs in the Vertex AI client construction (`app/pipeline/llm_client.py`):
- First, `google.genai.errors.ClientError: 404 ... /v1beta1/.../gemini-2.5-flash:generateContent`
  — this SDK version defaults Vertex AI calls to `v1beta1`, which 404s. Fixed by forcing
  `http_options=types.HttpOptions(api_version="v1")`.
- Still 404 after that fix, now against `.../v1/...`. The response was the *same generic
  Google 404 HTML* as bug #4 — the tell that the request never reached a real backend.
  With `location="global"`, the SDK's default host-building logic produces
  `global-aiplatform.googleapis.com`, which doesn't exist (`global` is not a valid
  regional host prefix — the un-prefixed `aiplatform.googleapis.com` is what serves the
  global endpoint, as the direct REST check in [ADR 0001](../adr/0001-gemini-2.5-flash-global-endpoint.md)
  used). **Fix**: also set `base_url="https://aiplatform.googleapis.com"` explicitly in
  `http_options`.

## 6. A human operator can't get an audience-scoped identity token for a private Cloud Run service
`gcloud auth print-identity-token --audiences=<service-url>` failed with *"Invalid
account type for `--audiences`. Requires valid service account"* when run as a human
Google account — a human's own OIDC token has a fixed audience (Google's own OAuth
client), not an arbitrary one, so Cloud Run's private-ingress check rejects it (with a
generic 404, matching bugs #4/#5's signature, not a 403 — Cloud Run deliberately doesn't
reveal whether an unauthenticated/misauthenticated caller even has the right target).
**Fix**: grant the operator `roles/iam.serviceAccountTokenCreator` on
`agent-eval-runner`'s service account (which already holds `run.invoker` on the pipeline
service) and impersonate it: `scripts/lib.sh::operator_token()` tries the direct call
first (works for a service-account identity, e.g. in CI) and falls back to impersonation
for a human operator.

## 7. A brand-new log-based metric isn't immediately usable in an alert policy
A from-scratch `terraform apply` (all resources created in one run) failed creating both
alert policies: *"Cannot find metric(s) that match type = ... could take up to 10 minutes
to become available."* `depends_on` on the metric resource only orders resource
*creation*, not the Monitoring API's server-side propagation delay after that. **Fix**:
`terraform/monitoring.tf` adds a `time_sleep` resource (90s) that the log-based metrics
must complete before, and both alert policies depend on the sleep, not just the metrics.

## 8. A freshly-created Cloud Run service's IAM binding isn't instantly enforced
The very first call to `/ask` immediately after a from-scratch `up.sh` created the
service got a **platform-level 403** (`Your client does not have permission to get URL
/ask from this server` — Cloud Run's own front end, not this app), even though
`roles/run.invoker` was already granted to the caller in the same `terraform apply`.
Retrying ~60-90s later succeeded. **Fix**: `scripts/up.sh`'s smoke-test step now retries
for up to 3 minutes (`wait_for` in `scripts/lib.sh`) instead of failing on the first
attempt.

## Other operational notes
- **IAM propagation lag**: the very first `roles/iam.serviceAccountTokenCreator` grant
  and the very first log-based metric took up to ~30s before alert policies/impersonation
  referencing them stopped erroring. Not a bug — just don't assume instant consistency
  immediately after `terraform apply`.
- **`gcloud alpha monitoring policies list`** requires installing the `alpha` gcloud
  component interactively. `scripts/test.sh` calls the Monitoring REST API directly with
  `gcloud auth print-access-token` instead, so the test suite doesn't need that
  component installed.
