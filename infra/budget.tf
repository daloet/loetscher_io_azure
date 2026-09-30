# Subscription-wide monthly budget (alerts only). Already applied; the
# resource address azurerm_consumption_budget_subscription.monthly must not change.

data "azurerm_subscription" "current" {}

# NOTE: An Azure budget only sends ALERTS. It does NOT cap or stop spending.
resource "azurerm_consumption_budget_subscription" "monthly" {
  name            = "budget-monthly-subscription"
  subscription_id = data.azurerm_subscription.current.id

  amount     = var.budget_amount
  time_grain = "Monthly"

  time_period {
    # Azure requires the start date to be the first day of a month and rejects
    # start dates in past months, so compute the first day of the CURRENT month
    # at apply time instead of hardcoding a date.
    start_date = formatdate("YYYY-MM-01'T'00:00:00Z", timestamp())
  }

  lifecycle {
    # timestamp() changes on every run; ignore time_period after creation so
    # later plans don't show a perpetual diff or try to move the start date.
    ignore_changes = [time_period]
  }

  notification {
    enabled        = true
    threshold      = 20
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.budget_alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Actual"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.budget_alert_email]
  }

  notification {
    enabled        = true
    threshold      = 100
    threshold_type = "Forecasted"
    operator       = "GreaterThanOrEqualTo"
    contact_emails = [var.budget_alert_email]
  }
}
