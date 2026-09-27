resource "google_cloud_scheduler_job" "eval_daily" {
  count       = var.image_job == "" ? 0 : 1
  project     = var.project_id
  region      = var.region
  name        = "agent-eval-daily"
  description = "Runs the golden-set evaluation against the deployed agent pipeline."
  schedule    = var.schedule_cron
  time_zone   = "Etc/UTC"

  http_target {
    http_method = "POST"
    uri         = "https://${var.region}-run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.eval_runner[0].name}:run"
    oauth_token {
      service_account_email = local.sa_email["agent-scheduler"]
    }
  }

  depends_on = [google_cloud_run_v2_job_iam_member.scheduler_invoker]
}
