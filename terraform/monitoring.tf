# Log-based metrics extracted from the structured JSON stdout lines the app/judge
# code emits (see app/pipeline/llm_client.py, pipeline.py, app/judge/run_golden_set.py).
# Cloud Run ships stdout to Cloud Logging automatically; these metrics are the bridge
# from "a log line happened" to "a number Cloud Monitoring can chart and alert on".
#
# cost_usd/latency_ms/eval_overall_score are DISTRIBUTION-typed (GCP log-based metrics
# only support a value_extractor on a DISTRIBUTION metric — a plain DOUBLE gauge with a
# value extractor is rejected outright). guardrail_block_count is a plain INT64 counter
# (no value_extractor, just a count of matching log lines). Both facts were found live
# on the first apply — see docs/runbooks/03-troubleshooting.md.

resource "google_logging_metric" "llm_call_cost_usd" {
  project     = var.project_id
  name        = "agent_obs/llm_call_cost_usd"
  description = "Cost (USD) of each logged Gemini call, by agent and model."
  filter      = "resource.type=\"cloud_run_revision\" AND jsonPayload.message=\"llm_call\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "USD"
    labels {
      key        = "agent"
      value_type = "STRING"
    }
    labels {
      key        = "model"
      value_type = "STRING"
    }
  }
  value_extractor = "EXTRACT(jsonPayload.cost_usd)"
  label_extractors = {
    agent = "EXTRACT(jsonPayload.agent)"
    model = "EXTRACT(jsonPayload.model)"
  }
  bucket_options {
    exponential_buckets {
      num_finite_buckets = 20
      growth_factor      = 2
      scale              = 0.0001
    }
  }
}

resource "google_logging_metric" "llm_call_latency_ms" {
  project     = var.project_id
  name        = "agent_obs/llm_call_latency_ms"
  description = "Latency (ms) of each logged Gemini call, by agent."
  filter      = "resource.type=\"cloud_run_revision\" AND jsonPayload.message=\"llm_call\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    unit        = "ms"
    labels {
      key        = "agent"
      value_type = "STRING"
    }
  }
  value_extractor = "EXTRACT(jsonPayload.latency_ms)"
  label_extractors = {
    agent = "EXTRACT(jsonPayload.agent)"
  }
  bucket_options {
    exponential_buckets {
      num_finite_buckets = 20
      growth_factor      = 2
      scale              = 10
    }
  }
}

resource "google_logging_metric" "guardrail_block_count" {
  project     = var.project_id
  name        = "agent_obs/guardrail_block_count"
  description = "Count of guardrail blocks, by direction and reason."
  filter      = "resource.type=\"cloud_run_revision\" AND jsonPayload.message=\"guardrail_block\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "INT64"
    labels {
      key        = "direction"
      value_type = "STRING"
    }
    labels {
      key        = "reason"
      value_type = "STRING"
    }
  }
  label_extractors = {
    direction = "EXTRACT(jsonPayload.direction)"
    reason    = "EXTRACT(jsonPayload.reason)"
  }
}

resource "google_logging_metric" "eval_overall_score" {
  project     = var.project_id
  name        = "agent_obs/eval_overall_score"
  description = "LLM-judge overall score (1-5) per golden-set question per run."
  filter      = "resource.type=\"cloud_run_job\" AND jsonPayload.message=\"eval_score\""
  metric_descriptor {
    metric_kind = "DELTA"
    value_type  = "DISTRIBUTION"
    labels {
      key        = "question_id"
      value_type = "STRING"
    }
  }
  value_extractor = "EXTRACT(jsonPayload.overall)"
  label_extractors = {
    question_id = "EXTRACT(jsonPayload.question_id)"
  }
  bucket_options {
    linear_buckets {
      num_finite_buckets = 5
      width              = 1
      offset             = 0
    }
  }
}

# A brand-new log-based metric isn't immediately queryable by the Monitoring API — a
# fresh `terraform apply` hit "Cannot find metric(s) ... could take up to 10 minutes to
# become available" when the alert policies below were created in the same apply as the
# metrics they reference (see docs/runbooks/03-troubleshooting.md). depends_on alone
# doesn't help since the dependency is server-side propagation, not resource creation
# order — hence the explicit wait.
resource "time_sleep" "wait_for_log_metrics" {
  depends_on = [
    google_logging_metric.llm_call_cost_usd,
    google_logging_metric.llm_call_latency_ms,
    google_logging_metric.guardrail_block_count,
    google_logging_metric.eval_overall_score,
  ]
  create_duration = "90s"
}

resource "google_monitoring_notification_channel" "email" {
  project      = var.project_id
  display_name = "agent-obs-platform alert email"
  type         = "email"
  labels = {
    email_address = var.alert_email
  }
}

# Threshold, not a trailing z-score like gcp-finops-cost-anomaly-detector: a short demo
# session doesn't accumulate the history a baseline needs. See
# docs/adr/0004-threshold-alerts-not-trailing-baseline.md.
resource "google_monitoring_alert_policy" "cost_spike" {
  project      = var.project_id
  display_name = "agent-obs: LLM call cost spike"
  combiner     = "OR"
  conditions {
    # cost_usd is logged per-call as a DISTRIBUTION metric (see monitoring.tf comment
    # above); a DISTRIBUTION can't be compared to a scalar threshold without first
    # collapsing it via a percentile aligner (GCP API rejected ALIGN_SUM here on the
    # first live apply — see docs/runbooks/03-troubleshooting.md). p99 per-call cost is
    # a reasonable "did one call cost way more than expected" signal at this scale.
    display_name = "p99 per-call cost_usd over 5 min exceeds threshold"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.llm_call_cost_usd.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = var.cost_alert_threshold_usd
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_PERCENTILE_99"
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  depends_on            = [time_sleep.wait_for_log_metrics]
}

resource "google_monitoring_alert_policy" "guardrail_violation_rate" {
  project      = var.project_id
  display_name = "agent-obs: guardrail violation rate"
  combiner     = "OR"
  conditions {
    display_name = "Any guardrail block in a 5 min window"
    condition_threshold {
      filter          = "resource.type=\"cloud_run_revision\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.guardrail_block_count.name}\""
      comparison      = "COMPARISON_GT"
      threshold_value = 0
      duration        = "0s"
      aggregations {
        alignment_period   = "300s"
        per_series_aligner = "ALIGN_SUM"
      }
    }
  }
  notification_channels = [google_monitoring_notification_channel.email.id]
  depends_on            = [time_sleep.wait_for_log_metrics]
}

resource "google_monitoring_dashboard" "agent_obs" {
  project = var.project_id
  dashboard_json = jsonencode({
    displayName = "Agent Cost & Observability"
    mosaicLayout = {
      columns = 12
      tiles = [
        {
          width = 6, height = 4,
          widget = {
            title = "LLM call cost (USD) by agent"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter      = "resource.type=\"cloud_run_revision\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.llm_call_cost_usd.name}\""
                    aggregation = { alignmentPeriod = "3600s", perSeriesAligner = "ALIGN_SUM", crossSeriesReducer = "REDUCE_SUM", groupByFields = ["metric.label.agent"] }
                  }
                }
                plotType = "STACKED_BAR"
              }]
            }
          }
        },
        {
          xPos = 6, width = 6, height = 4,
          widget = {
            title = "LLM call latency (ms) by agent"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter      = "resource.type=\"cloud_run_revision\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.llm_call_latency_ms.name}\""
                    aggregation = { alignmentPeriod = "300s", perSeriesAligner = "ALIGN_MEAN", crossSeriesReducer = "REDUCE_MEAN", groupByFields = ["metric.label.agent"] }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        },
        {
          yPos = 4, width = 6, height = 4,
          widget = {
            title = "Guardrail violations by reason"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter      = "resource.type=\"cloud_run_revision\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.guardrail_block_count.name}\""
                    aggregation = { alignmentPeriod = "3600s", perSeriesAligner = "ALIGN_SUM", crossSeriesReducer = "REDUCE_SUM", groupByFields = ["metric.label.reason"] }
                  }
                }
                plotType = "STACKED_BAR"
              }]
            }
          }
        },
        {
          xPos = 6, yPos = 4, width = 6, height = 4,
          widget = {
            title = "Eval score trend (LLM-judge overall, 1-5)"
            xyChart = {
              dataSets = [{
                timeSeriesQuery = {
                  timeSeriesFilter = {
                    filter      = "resource.type=\"cloud_run_job\" AND metric.type=\"logging.googleapis.com/user/${google_logging_metric.eval_overall_score.name}\""
                    aggregation = { alignmentPeriod = "86400s", perSeriesAligner = "ALIGN_MEAN", crossSeriesReducer = "REDUCE_MEAN" }
                  }
                }
                plotType = "LINE"
              }]
            }
          }
        }
      ]
    }
  })
}
