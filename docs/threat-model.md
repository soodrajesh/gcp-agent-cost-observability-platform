# Threat model (STRIDE)

Focus areas per the brief: prompt-injection and data-exfiltration-via-agent threats get
the most attention, since this repo is specifically about agent safety and cost
governance, not just "an app on Cloud Run".

| # | STRIDE category | Threat | Control | Proven by |
|---|---|---|---|---|
| T1 | **Spoofing** | Anonymous caller invokes the pipeline service directly, running up Vertex AI spend on someone else's bill | No `allUsers` binding on `agent-pipeline`; only `agent-eval-runner`'s SA and the admin's own identity hold `roles/run.invoker` (ADR 0006) | `scripts/test.sh` §1–2 call with a real ID token; an unauthenticated `curl` returns 403 (not exercised as a numbered test to avoid a noisy failing call in the suite, but verifiable manually) |
| T2 | **Spoofing** | A forged/replayed OIDC token lets something other than Cloud Scheduler trigger the eval-runner Job on demand, running up cost | `roles/run.invoker` on the Job is scoped to exactly the `agent-scheduler` SA; Cloud Run validates the token's signature and audience | IAM policy check in `scripts/test.sh` §5 confirms no broader binding exists |
| T3 | **Tampering** | Prompt-injection: a user's question contains instructions trying to override the pipeline's system instructions ("ignore previous instructions...") | Input guardrail (`guardrails.check_input`) runs before any Gemini call and blocks known injection phrasings; system instructions are passed via the `system_instruction` config field (a channel Gemini weighs more heavily than user content), not concatenated into the user turn | `scripts/test.sh` §4: golden-set `q8` sends a canonical injection attempt and the response is `block_stage=input` with zero Gemini calls made for that request |
| T4 | **Tampering** | **Indirect prompt injection via tool output**: if the `query_spend` tool's output ever contained attacker-controlled text (e.g., if this were pointed at a real, externally-writable data source), the worker or reviewer could be steered into following instructions embedded in "data" | The reviewer step is explicitly instructed to treat tool results only as ground-truth numbers to check the draft against, not as instructions; the output guardrail's secret-shaped-string check catches an answer that echoes something that looks exfiltrated rather than a legitimate figure | Threat is structurally reduced (the fixture tool returns only numeric fields, no free text) but not adversarially tested with a poisoned tool response in this build — see Known gaps |
| T5 | **Repudiation** | No record of what a given agent step actually said or why an answer was produced | Every Gemini call is logged to `llm_calls` with the exact prompt, response, agent, step, and request_id; every guardrail decision is logged to `guardrail_events` | `scripts/test.sh` §3: BigQuery query confirms >=3 logged calls (planner/worker/reviewer) for a real request_id |
| T6 | **Information Disclosure — data exfiltration via the agent** | The agent is tricked into revealing secrets, credentials, or its own system instructions in its answer | Output guardrail's Vertex AI safety-rating check + explicit secret-shaped-string regex (API-key/private-key shapes) blocks matching output before it's returned to the caller; the fixture dataset itself contains no secrets, so this is a structural check for the shape of leaked material, not reliance on the model "choosing" not to leak | Unit tests `app/pipeline/tests/test_guardrails.py::test_output_guardrail_catches_secret_shaped_string`; not exercised end-to-end live in `scripts/test.sh` because provoking a real secret-shaped hallucination on demand is not reliable — see Known gaps |
| T7 | **Information Disclosure** | BigQuery dataset (containing full prompts/responses) is readable by more than the pipeline and the operator | `bigquery.dataEditor` is granted only to `agent-pipeline` and `agent-eval-runner` SAs at the **dataset** level (not project-wide); the operator gets `bigquery.dataViewer` at the project level for verification, nothing broader | `scripts/test.sh` §5 IAM check; `terraform/identities.tf` |
| T8 | **Denial of Service** | Unbounded or looping tool-calling drives runaway Vertex AI spend | Worker's tool-call loop is hard-capped at 3 round trips (`agents.py::run_worker`); Cloud Run request timeout and `max-instance-count=3` bound concurrency; the cost-spike alert policy pages if summed cost crosses a threshold in a 5-minute window | Code inspection (`agents.py`); `terraform/monitoring.tf` cost-spike policy exists (`scripts/test.sh` §8) |
| T9 | **Elevation of Privilege** | Any of this repo's service accounts is over-permissioned (project owner/editor, or a broader role than its job needs) | Four dedicated SAs, each with only the roles listed in `terraform/identities.tf`; no `roles/owner` or `roles/editor` anywhere; no service-account keys | `scripts/test.sh` §5–6: IAM policy grep for owner/editor, and a key-count check across all four SAs |
| T10 | **Elevation of Privilege** | The eval-runner Job is able to do more than call the pipeline and write eval scores (e.g., could it modify the pipeline's own BigQuery rows, or invoke other services?) | `agent-eval-runner`'s IAM grants are: `aiplatform.user`, `bigquery.dataEditor` on the one dataset, `roles/run.invoker` on the one service — nothing else | `terraform/identities.tf`; `scripts/test.sh` §5 |

## Known gaps (not adversarially tested in this build)
- **Indirect injection via tool output (T4)** is structurally reduced but not tested with
  a deliberately poisoned tool response, since the fixture tool returns only numeric
  fields with no free text channel for an attacker to inject through.
- **Live exfiltration provocation (T6)** relies on a unit test with a synthetic
  secret-shaped string, not a live attempt to get the deployed model to actually emit one
  — reliably provoking that on demand from a well-behaved model is not a repeatable live
  test.
- **No VPC Service Controls perimeter** around the BigQuery dataset — IAM is the only
  boundary. A production deployment handling non-fixture data should add one.
- **No rate limiting / per-caller quota** beyond Cloud Run's own concurrency and instance
  caps — a single authenticated caller could still drive meaningful spend before the
  cost-spike alert fires (it does not auto-block, only pages).
