variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "admin_email" {
  type = string
}

variable "alert_email" {
  type = string
}

variable "budget_amount" {
  description = "Monthly budget in EUR that triggers Billing Budget alerts."
  type        = number
  default     = 15
}

variable "billing_account_id" {
  type = string
}

variable "image_service" {
  description = "Digest-pinned image for the agent-pipeline Cloud Run service. Empty = phase 1 (infra only)."
  type        = string
  default     = ""
}

variable "image_job" {
  description = "Digest-pinned image for the agent-eval-runner Cloud Run Job. Empty = phase 1 (infra only)."
  type        = string
  default     = ""
}

variable "schedule_cron" {
  description = "Cloud Scheduler cron for the daily golden-set evaluation run."
  type        = string
  default     = "0 7 * * *"
}

variable "cost_alert_threshold_usd" {
  description = "Alert if summed logged LLM-call cost exceeds this many USD within the alignment window."
  type        = number
  default     = 1.0
}
