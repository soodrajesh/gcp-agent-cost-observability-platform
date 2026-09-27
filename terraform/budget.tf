# A backstop, not the primary control (the ADR-0004-equivalent alert policies below do
# the real-time work) — bounds total project spend regardless of what this repo does.
resource "google_billing_budget" "this" {
  billing_account = var.billing_account_id
  display_name    = "gcp-agent-cost-observability-platform"

  budget_filter {
    projects = ["projects/${data.google_project.this.number}"]
  }

  amount {
    specified_amount {
      currency_code = "EUR"
      units         = tostring(var.budget_amount)
    }
  }

  threshold_rules { threshold_percent = 0.5 }
  threshold_rules { threshold_percent = 0.9 }
  threshold_rules { threshold_percent = 1.0 }
}
