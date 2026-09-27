#!/usr/bin/env bash
# Build the whole platform end to end, then prove it works:
#   state bucket -> BigQuery/IAM/monitoring/budget/registry -> build both images
#   -> Cloud Run service + job + scheduler -> seed SYNTHETIC eval history
#   -> run the golden set once live -> live tests.
# Two Terraform phases: the service/job need image digests, so infra comes first.
source "$(dirname "$0")/lib.sh"
PLAN_ONLY=0; SKIP_TESTS=0
for a in "$@"; do case "$a" in --plan) PLAN_ONLY=1;; --skip-tests) SKIP_TESTS=1;; esac; done
need gcloud; need terraform; need bq; need python3

log "Project $PROJECT_ID · $REGION · billing $BILLING_ACCOUNT_ID · admin $ADMIN_EMAIL"
log "1/8 Terraform state bucket"
"$ROOT/scripts/bootstrap.sh" "$PROJECT_ID" "$REGION" >/dev/null && ok "gs://$STATE_BUCKET"
tf_init
[ "$PLAN_ONLY" = 1 ] && { $TF plan -input=false; exit 0; }

log "2/8 Phase 1: BigQuery dataset + tables, IAM, monitoring, budget, registry"
# Re-runs must not tear down the running service/job (phase 2): keep previous images.
if [ -s "$ROOT/.last-image-service" ]; then TF_VAR_image_service="$(cat "$ROOT/.last-image-service")"; export TF_VAR_image_service; fi
if [ -s "$ROOT/.last-image-job" ]; then TF_VAR_image_job="$(cat "$ROOT/.last-image-job")"; export TF_VAR_image_job; fi
$TF apply -input=false -auto-approve
out() { $TF output -raw "$1"; }
REPO="$(out artifact_repo)"; BUCKET="$(out build_bucket)"; BUILD_SA="$(out build_sa)"
DATASET="$(out dataset)"

log "3/8 Build both images (Cloud Build, dedicated least-privilege SA)"
TAG="v$(date +%y%m%d-%H%M%S)"
gcloud builds submit --project "$PROJECT_ID" --region "$REGION" --config cloudbuild.yaml \
  --service-account "projects/$PROJECT_ID/serviceAccounts/$BUILD_SA" \
  --gcs-source-staging-dir "gs://$BUCKET/src" --substitutions "_REPO=$REPO,_TAG=$TAG" .
SVC_DIGEST="$(gcloud artifacts docker images describe "$REPO/pipeline:$TAG" --format='get(image_summary.digest)')"
JOB_DIGEST="$(gcloud artifacts docker images describe "$REPO/eval-runner:$TAG" --format='get(image_summary.digest)')"
IMG_SVC="$REPO/pipeline@$SVC_DIGEST"; IMG_JOB="$REPO/eval-runner@$JOB_DIGEST"
echo "$IMG_SVC" > "$ROOT/.last-image-service"; echo "$IMG_JOB" > "$ROOT/.last-image-job"
ok "pipeline image $IMG_SVC"; ok "eval-runner image $IMG_JOB"

log "4/8 Phase 2: Cloud Run service + job + Scheduler + IAM bindings"
export TF_VAR_image_service="$IMG_SVC" TF_VAR_image_job="$IMG_JOB"
$TF apply -input=false -auto-approve
SERVICE_URL="$(out service_url)"; JOB="$(out job_name)"
ok "service $SERVICE_URL"; ok "job $JOB"

log "5/8 Seed SYNTHETIC eval-score history (docs/adr/0002 — clearly labelled, not real)"
python3 "$ROOT/seed/generate_synthetic_eval_history.py"
bq --project_id "$PROJECT_ID" load --source_format=NEWLINE_DELIMITED_JSON \
  "${DATASET}.eval_scores" "$ROOT/seed/synthetic_eval_history.jsonl"
ROWS="$(bq_scalar "SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.eval_scores\` WHERE is_synthetic")"
ok "loaded $ROWS synthetic eval_scores rows"

log "6/8 Smoke test: one live call through the deployed pipeline"
TOKEN="$(operator_token "$SERVICE_URL")"
# A freshly-created service's run.invoker IAM binding can take up to ~1-2 minutes to
# propagate (found live on a from-scratch run: the first call after creation got a
# platform-level 403, not this app's guardrail). Retry rather than fail immediately.
SMOKE_TMP="$ROOT/.test-tmp"; mkdir -p "$SMOKE_TMP"
wait_for "IAM propagation + smoke-test call succeeds" 180 \
  curl -sf -X POST "$SERVICE_URL/ask" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"question":"What was BigQuery'"'"'s spend in August 2026?"}' -o "$SMOKE_TMP/smoke.json"
python3 -m json.tool "$SMOKE_TMP/smoke.json"

log "7/8 Run the golden set once now (real LLM-judged run, is_synthetic=false)"
EXEC="$(gcloud run jobs execute "$JOB" --project "$PROJECT_ID" --region "$REGION" --wait --format='value(metadata.name)')"
ok "eval-runner execution $EXEC finished"

if [ "$SKIP_TESTS" = 1 ]; then log "Skipping tests"; else log "8/8 Live test suite"; "$ROOT/scripts/test.sh"; fi
log "DONE — tear down with ./scripts/down.sh"
