# Pipeline service: authenticated only (no allUsers binding) — invoked by the
# eval-runner job and by the human operator's own identity, never anonymously.
resource "google_cloud_run_v2_service" "pipeline" {
  count               = var.image_service == "" ? 0 : 1
  project             = var.project_id
  name                = "agent-pipeline"
  location            = var.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = local.sa_email["agent-pipeline"]
    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }
    containers {
      image = var.image_service
      ports { container_port = 8080 }
      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "BQ_DATASET"
        value = google_bigquery_dataset.agent_observability.dataset_id
      }
      resources {
        limits = { cpu = "1", memory = "512Mi" }
      }
      startup_probe {
        http_get { path = "/livez" }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 6
      }
    }
  }
  depends_on = [
    google_bigquery_dataset_iam_member.pipeline_dataset_editor,
    google_project_iam_member.pipeline_vertex_user,
    google_project_iam_member.pipeline_log_writer,
  ]
}

# Eval runner: a Job, not a Service — no inbound traffic, runs on a schedule (or
# on-demand), exits when done, bills nothing between runs. Mirrors the same
# Job-over-Function/Service reasoning as gcp-finops-cost-anomaly-detector ADR 0001.
resource "google_cloud_run_v2_job" "eval_runner" {
  count               = var.image_job == "" ? 0 : 1
  project             = var.project_id
  name                = "agent-eval-runner"
  location            = var.region
  deletion_protection = false

  template {
    template {
      service_account = local.sa_email["agent-eval-runner"]
      max_retries     = 0
      timeout         = "540s"
      containers {
        image = var.image_job
        env {
          name  = "PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "BQ_DATASET"
          value = google_bigquery_dataset.agent_observability.dataset_id
        }
        env {
          name  = "SERVICE_URL"
          value = var.image_service == "" ? "" : google_cloud_run_v2_service.pipeline[0].uri
        }
        resources {
          limits = { cpu = "1", memory = "512Mi" }
        }
      }
    }
  }
  depends_on = [
    google_bigquery_dataset_iam_member.eval_dataset_editor,
    google_project_iam_member.eval_vertex_user,
    google_project_iam_member.eval_log_writer,
  ]
}
