# 0007: Subscription ID via environment variable

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

Version 4 of the `azurerm` Terraform provider requires a subscription ID. It can be written into the provider block, put in `terraform.tfvars`, or read from the `ARM_SUBSCRIPTION_ID` **environment variable** (a value set in the Terminal session, not stored in a file).

A subscription ID is not a password, but it is an identifier that helps attackers with targeting and phishing. It should not be in the public repository.

## Decision

- Do not store the subscription ID in any file. The provider block in `infra/versions.tf` has no `subscription_id`.
- Before running Terraform, set it from the current Azure CLI login:
  ```sh
  export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
  ```
- Locally, Terraform authenticates through the Azure CLI login (`az login`).

## Consequences

- The ID never ends up in Git, in `terraform.tfvars`, or in docs.
- Terraform always uses the subscription that `az` has selected. Check it with `az account show --query name -o tsv` before an apply.
- The variable must be set again in every new Terminal window. If it is missing, Terraform stops with an error (see the [runbook](../runbook.md#error-about-a-missing-subscription_id)).
- Terraform output such as `budget_id` still contains the subscription ID inside resource IDs. Do not paste it publicly.
- A future CI workflow would set `ARM_SUBSCRIPTION_ID` from a GitHub secret.
