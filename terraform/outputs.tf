output "artifact_repo" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.images.repository_id}"
}

output "build_bucket" {
  value = google_storage_bucket.build.name
}

output "build_sa" {
  value = local.sa_email["agent-build"]
}

output "dataset" {
  value = google_bigquery_dataset.agent_observability.dataset_id
}

output "service_name" {
  value = var.image_service == "" ? "" : google_cloud_run_v2_service.pipeline[0].name
}

output "service_url" {
  value = var.image_service == "" ? "" : google_cloud_run_v2_service.pipeline[0].uri
}

output "job_name" {
  value = var.image_job == "" ? "" : google_cloud_run_v2_job.eval_runner[0].name
}
