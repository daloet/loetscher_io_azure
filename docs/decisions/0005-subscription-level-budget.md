# 0005: Subscription-level budget with an early warning

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

The project aims to cost 0 per month. The Static Web App Free tier has no charge, but a mistake (for example a paid SKU, or a resource created by hand) could still cause costs. Azure can send cost alerts through a **budget**: a monthly amount with email notifications at chosen percentages.

A budget can be set on a resource group or on the whole subscription. A resource-group budget would miss costs from anything outside `rg-loetscher-web`. The billing currency of the account is CHF.

## Decision

- Create one budget on the **whole subscription**: `budget-monthly-subscription`, defined in `infra/budget.tf` (moved from `main.tf` in Step 3) as `azurerm_consumption_budget_subscription.monthly`.
- Amount: **5 CHF per month** (`budget_amount`, default `5`, in the billing currency).
- Alerts by email to `<budget-alert-email>`:
  - **20% actual** (1 CHF): an early warning. The expected cost is 0, so any real spend at all is worth knowing about.
  - **100% actual**: the budget has been used up.
  - **100% forecast**: Azure predicts the month will reach the budget.
- The start date is the first day of the month in which it is applied, computed at apply time. After creation, Terraform ignores changes to the time period. The budget runs from 2026-09-01 to 2036-09-01.
- Apply the budget first, on its own, before any other resource exists (Step 2), so cost alerts are active from the start.

## Consequences

- Any unexpected cost anywhere in the subscription triggers an email early.
- **A budget only alerts. It does NOT cap or stop spending.** If an alert arrives, a person must act (see the [runbook](../runbook.md#check-the-budget)).
- Azure cost data is updated with a delay of several hours, so alerts are not instant.
- The budget also covers anything else in the same subscription, which may cause alerts unrelated to this project.
- Running `terraform destroy` also deletes the budget.
