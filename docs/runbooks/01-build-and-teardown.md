# 01 — Build & teardown

## Build
```bash
gcloud config set project <your-project>   # billing linked; region defaults to europe-west1
./scripts/up.sh
```
One script does everything: state bucket → Terraform phase 1 (BigQuery, IAM, monitoring,
budget, Artifact Registry) → build both container images with Cloud Build → Terraform
phase 2 (Cloud Run service + job, Scheduler, IAM bindings that depend on the images) →
seed synthetic eval history → smoke test → run the golden set live once → full live test
suite (`scripts/test.sh`).

Flags:
- `--plan` — run `terraform plan` and stop (no resources created, no image build).
- `--skip-tests` — build everything but skip the final `scripts/test.sh` call.

Re-running `up.sh` is safe: phase 1 preserves whatever image is currently deployed
(via `.last-image-service` / `.last-image-job`) so a re-run doesn't tear down the running
service, then phase 2 rolls forward to the newly built images.

## Teardown
```bash
./scripts/down.sh            # destroys the platform; keeps the small shared state bucket
./scripts/down.sh --purge    # also deletes this repo's Terraform state prefix
```
`down.sh` prints a checklist of every resource category this repo creates (Cloud Run
service/job, Scheduler job, BigQuery dataset, Artifact Registry repo, build bucket,
service accounts, billing budget) with a live count after destruction — every line
should read 0.

## Configuration
`scripts/lib.sh` reads `deploy.env` if present (see `example.tfvars` for the equivalent
Terraform variables). Everything else is auto-detected from `gcloud config`.
