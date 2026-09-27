resource "google_bigquery_dataset" "agent_observability" {
  project                    = var.project_id
  dataset_id                 = "agent_observability"
  location                   = var.region
  delete_contents_on_destroy = true
  depends_on                 = [google_project_service.apis]
}

resource "google_bigquery_table" "llm_calls" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.agent_observability.dataset_id
  table_id            = "llm_calls"
  deletion_protection = false
  schema = jsonencode([
    { name = "request_id", type = "STRING", mode = "REQUIRED" },
    { name = "timestamp", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "agent", type = "STRING", mode = "REQUIRED" },
    { name = "step", type = "INT64", mode = "REQUIRED" },
    { name = "model", type = "STRING", mode = "REQUIRED" },
    { name = "prompt", type = "STRING", mode = "NULLABLE" },
    { name = "response_text", type = "STRING", mode = "NULLABLE" },
    { name = "input_tokens", type = "INT64", mode = "REQUIRED" },
    { name = "output_tokens", type = "INT64", mode = "REQUIRED" },
    { name = "thoughts_tokens", type = "INT64", mode = "REQUIRED" },
    { name = "cost_usd", type = "FLOAT64", mode = "REQUIRED" },
    { name = "latency_ms", type = "FLOAT64", mode = "REQUIRED" },
    { name = "had_function_call", type = "BOOL", mode = "REQUIRED" },
    { name = "is_synthetic", type = "BOOL", mode = "REQUIRED" },
  ])
}

resource "google_bigquery_table" "guardrail_events" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.agent_observability.dataset_id
  table_id            = "guardrail_events"
  deletion_protection = false
  schema = jsonencode([
    { name = "request_id", type = "STRING", mode = "REQUIRED" },
    { name = "timestamp", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "direction", type = "STRING", mode = "REQUIRED" },
    { name = "reason", type = "STRING", mode = "REQUIRED" },
    { name = "blocked", type = "BOOL", mode = "REQUIRED" },
    { name = "details_json", type = "STRING", mode = "NULLABLE" },
  ])
}

resource "google_bigquery_table" "eval_scores" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.agent_observability.dataset_id
  table_id            = "eval_scores"
  deletion_protection = false
  schema = jsonencode([
    { name = "run_id", type = "STRING", mode = "REQUIRED" },
    { name = "question_id", type = "STRING", mode = "REQUIRED" },
    { name = "scored_at", type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "correctness", type = "INT64", mode = "REQUIRED" },
    { name = "completeness", type = "INT64", mode = "REQUIRED" },
    { name = "safety", type = "INT64", mode = "REQUIRED" },
    { name = "overall", type = "FLOAT64", mode = "REQUIRED" },
    { name = "judge_notes", type = "STRING", mode = "NULLABLE" },
    { name = "is_synthetic", type = "BOOL", mode = "REQUIRED" },
  ])
}
