#!/usr/bin/env bash
# Delete everything this repo created, end to end.
#   ./scripts/down.sh            destroy the platform (keeps the tiny shared Terraform state bucket)
#   ./scripts/down.sh --purge    also delete this repo's Terraform state (and the bucket if now empty)
source "$(dirname "$0")/lib.sh"
need gcloud; need terraform
PURGE=0; [ "${1:-}" = "--purge" ] && PURGE=1

log "Project $PROJECT_ID — destroying everything managed by this repo"
tf_init
TF_VAR_image_service="$(cat "$ROOT/.last-image-service" 2>/dev/null || echo "")"; export TF_VAR_image_service
TF_VAR_image_job="$(cat "$ROOT/.last-image-job" 2>/dev/null || echo "")"; export TF_VAR_image_job
log "1/2 Terraform destroy (Cloud Run service+job, Scheduler, BigQuery dataset incl. data, monitoring, budget, registry, bucket)"
$TF destroy -input=false -auto-approve
ok "platform destroyed"
rm -f "$ROOT/.last-image-service" "$ROOT/.last-image-job" "$ROOT/seed/synthetic_eval_history.jsonl"
rm -rf "$ROOT/.test-tmp"

if [ "$PURGE" = 1 ]; then
  log "2/2 Purging this repo's Terraform state"
  gcloud storage rm -r "gs://$STATE_BUCKET/agent-obs-platform/" --quiet >/dev/null 2>&1 || true
  if [ -z "$(gcloud storage ls "gs://$STATE_BUCKET/" 2>/dev/null)" ]; then
    gcloud storage rm -r "gs://$STATE_BUCKET" --quiet >/dev/null 2>&1 || true; ok "state prefix and (now empty) bucket removed"
  else ok "state prefix removed; bucket kept because other stacks still use it"; fi
else log "2/2 Kept state bucket gs://$STATE_BUCKET (a few KB; --purge removes it)"; fi

log "Anything billable left?"
echo "  Cloud Run services (agent-pipeline): $(gcloud run services list --project "$PROJECT_ID" --region "$REGION" --format='value(metadata.name)' 2>/dev/null | grep -c '^agent-pipeline$' || true)"
echo "  Cloud Run jobs (agent-eval-runner): $(gcloud run jobs list --project "$PROJECT_ID" --region "$REGION" --format='value(name)' 2>/dev/null | grep -c '^agent-eval-runner$' || true)"
echo "  Cloud Scheduler jobs: $(gcloud scheduler jobs list --project "$PROJECT_ID" --location "$REGION" --format='value(name)' 2>/dev/null | grep -c 'agent-eval-daily' || true)"
echo "  BigQuery datasets (agent_observability): $(bq --project_id "$PROJECT_ID" ls -d 2>/dev/null | grep -c ' agent_observability *$' || true)"
echo "  Artifact Registry (agent-obs-platform): $(gcloud artifacts repositories list --project "$PROJECT_ID" --location "$REGION" --format='value(name)' 2>/dev/null | grep -c '/agent-obs-platform$' || true)"
echo "  Build bucket: $(gcloud storage ls "gs://${PROJECT_ID}-agent-obs-build" 2>/dev/null | wc -l | tr -d ' ')"
echo "  Service accounts (agent-*): $(gcloud iam service-accounts list --project "$PROJECT_ID" --format='value(email)' 2>/dev/null | grep -c '^agent-' || true)"
echo "  Billing budgets (gcp-agent-cost-observability-platform): $(gcloud billing budgets list --billing-account "$BILLING_ACCOUNT_ID" --format='value(displayName)' 2>/dev/null | grep -c '^gcp-agent-cost-observability-platform$' || true)"
log "DONE"
