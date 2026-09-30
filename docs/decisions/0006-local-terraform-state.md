# 0006: Local Terraform state

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

Terraform keeps a **state file**: its record of which cloud resources it created and their settings. The state can be stored locally (a file next to the code) or in a **remote backend** (a service that stores it, such as an Azure Storage account or HCP Terraform).

This is a one-person project with a goal of 0 cost and a simple setup.

## Decision

Keep the state local in `infra/terraform.tfstate`. It is gitignored (`*.tfstate` and `*.tfstate.*`) and never committed.

## Consequences

Good:

- Free and simple. No extra Azure resource and no extra account needed.

Bad, and how to handle it:

- **No locking.** Two runs at the same time could damage the state. Only one person runs Terraform, so this is acceptable.
- **No automatic backup.** If the file is lost, Terraform no longer knows about the resources. Keep a private backup after each apply.
- **Contains secrets in plain text.** Today the alert email; after Step 3 also the Static Web App deployment token. Never commit or share it. See [security](../security.md#local-terraform-state).
- **CI cannot use it.** A Terraform workflow in GitHub Actions (optional, Step 4) would need a remote backend.

Later option: move to an **Azure Storage backend** or the **HCP Terraform free tier**. Both add locking and backups. This would get its own ADR.
