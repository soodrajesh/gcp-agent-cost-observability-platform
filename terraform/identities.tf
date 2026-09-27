# One identity per job to be done. No service-account keys anywhere: Cloud Run uses its
# attached identity (ADC), Cloud Scheduler mints its own OIDC/OAuth token, Cloud Build
# uses its own dedicated SA. No project-level owner/editor role is granted to anything.
locals {
  sas = {
    "agent-pipeline"    = "Cloud Run service: the planner/worker/reviewer pipeline"
    "agent-eval-runner" = "Cloud Run Job: calls the deployed pipeline with the golden set, judges answers"
    "agent-scheduler"   = "Cloud Scheduler: may only start the eval-runner job"
    "agent-build"       = "Cloud Build: builds and pushes both container images"
  }
}

resource "google_service_account" "sa" {
  for_each     = local.sas
  project      = var.project_id
  account_id   = each.key
  display_name = each.value
  depends_on   = [google_project_service.apis]
}

locals {
  sa_email = { for k, v in google_service_account.sa : k => v.email }
}

# ── pipeline service: Vertex AI + its own dataset slice, nothing project-wide ──
resource "google_project_iam_member" "pipeline_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${local.sa_email["agent-pipeline"]}"
}

resource "google_bigquery_dataset_iam_member" "pipeline_dataset_editor" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.agent_observability.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${local.sa_email["agent-pipeline"]}"
}

resource "google_project_iam_member" "pipeline_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.sa_email["agent-pipeline"]}"
}

# ── eval runner: Vertex AI (for the judge call) + same dataset slice + invoke the service ──
resource "google_project_iam_member" "eval_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${local.sa_email["agent-eval-runner"]}"
}

resource "google_bigquery_dataset_iam_member" "eval_dataset_editor" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.agent_observability.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${local.sa_email["agent-eval-runner"]}"
}

resource "google_project_iam_member" "eval_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.sa_email["agent-eval-runner"]}"
}

resource "google_cloud_run_v2_service_iam_member" "eval_can_invoke_pipeline" {
  count    = var.image_service == "" ? 0 : 1
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.pipeline[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.sa_email["agent-eval-runner"]}"
}

# The human operator running scripts/test.sh also needs to invoke the private service
# and read BigQuery to verify results.
resource "google_cloud_run_v2_service_iam_member" "admin_can_invoke_pipeline" {
  count    = var.image_service == "" ? 0 : 1
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.pipeline[0].name
  role     = "roles/run.invoker"
  member   = "user:${var.admin_email}"
}

resource "google_project_iam_member" "admin_bq_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "user:${var.admin_email}"
}

resource "google_project_iam_member" "admin_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "user:${var.admin_email}"
}

# A human user's own Google Sign-In ID token is fixed-audience (Google's own OAuth
# client) and Cloud Run's private-ingress check rejects it — found live when
# `gcloud auth print-identity-token --audiences=<service-url>` errored with "Invalid
# account type" for a user account (see docs/runbooks/03-troubleshooting.md). The
# operator therefore impersonates agent-eval-runner's SA (which already holds
# run.invoker on the service) to mint a correctly-audienced token for manual/CI-free
# testing, rather than being granted a broader standing credential.
resource "google_service_account_iam_member" "admin_can_impersonate_eval_runner" {
  service_account_id = google_service_account.sa["agent-eval-runner"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.admin_email}"
}

# ── scheduler: only allowed to start the eval-runner job ──
resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  count    = var.image_job == "" ? 0 : 1
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.eval_runner[0].name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${local.sa_email["agent-scheduler"]}"
}

# ── build ──
resource "google_artifact_registry_repository" "images" {
  project       = var.project_id
  location      = var.region
  repository_id = "agent-obs-platform"
  format        = "DOCKER"
  depends_on    = [google_project_service.apis]
}

resource "google_storage_bucket" "build" {
  project                     = var.project_id
  name                        = "${var.project_id}-agent-obs-build"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = true
  lifecycle_rule {
    condition { age = 7 }
    action { type = "Delete" }
  }
}

resource "google_project_iam_member" "build_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${local.sa_email["agent-build"]}"
}

resource "google_artifact_registry_repository_iam_member" "build_push" {
  project    = var.project_id
  location   = var.region
  repository = google_artifact_registry_repository.images.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${local.sa_email["agent-build"]}"
}

resource "google_storage_bucket_iam_member" "build_src" {
  bucket = google_storage_bucket.build.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${local.sa_email["agent-build"]}"
}
