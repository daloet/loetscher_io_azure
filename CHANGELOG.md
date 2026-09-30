# Changelog

One entry per completed step, newest first.

## 2026-09-29: Step 3: Static Web App

- Split `infra/`: `budget.tf` holds the budget (unchanged), `main.tf` now holds the resource group, the Static Web App, and the custom domains.
- `versions.tf`: the provider registers only `Microsoft.Web` via `resource_providers_to_register`. This happens when the provider starts, so already during `terraform plan`.
- New variables: `static_web_app_location` (default `eastus2`, validated), `resource_group_name`, `static_web_app_name`, `apex_domain`, `enable_www_domain` (default `false`), `tags`. `terraform.tfvars.example` updated.
- First apply: created resource group `rg-loetscher-web` in `westeurope`. The Static Web App was rejected with `RequestDisallowedByAzure: The selected region is currently not accepting new customers`. Fixed by putting the Static Web App in `eastus2`; the resource group stays in `westeurope` ([ADR 0008](docs/decisions/0008-swa-region-eastus2.md)).
- Second apply: created Static Web App `swa-loetscher-web` (Free/Free, `eastus2`, preview environments on, config file changes on) and the apex custom domain `loetscher.io` (`dns-txt-token` validation; Terraform does not wait for it).
- The `www.loetscher.io` domain uses `cname-delegation`, which Azure validates immediately, so it is gated behind `enable_www_domain` and added after the DNS records exist ([ADR 0009](docs/decisions/0009-two-step-custom-domain-rollout.md)).
- New outputs: `default_host_name`, `dns_records` (`TXT @`, `ANAME @`, `CNAME www`), `deployment_token` (sensitive, never printed; for the GitHub secret in Step 4), and `budget_id`.
- Canonical host: apex `loetscher.io`; `www` will redirect to it via the portal's "default domain" setting in Step 5 ([ADR 0010](docs/decisions/0010-apex-as-canonical-host.md)).
- Security: the user confirmed there are no other loetscher.io subdomains, so HSTS `includeSubDomains` stays. The user removed the root-scope User Access Administrator. The local `terraform.tfstate` now contains the deployment token (gitignored; don't share it).
- Docs: added [setup section 9](docs/setup.md#9-static-web-app-and-custom-domains), [DNS records at Hostpoint](docs/runbook.md#dns-records-at-hostpoint) with `dig` checks, troubleshooting for the region error and DNS validation, and the planned token rotation steps. Updated the architecture diagram and [security](docs/security.md).
- Recorded decisions [0008](docs/decisions/0008-swa-region-eastus2.md), [0009](docs/decisions/0009-two-step-custom-domain-rollout.md), and [0010](docs/decisions/0010-apex-as-canonical-host.md). Added notes to [0002](docs/decisions/0002-azure-static-web-apps-free-tier.md) (region) and [0003](docs/decisions/0003-dns-at-hostpoint-manual-records.md) (canonical host resolved).

## 2026-09-29: Step 2: Budget alert

- Added a root `.gitignore`: Terraform state, `.terraform/`, `*.tfvars` (except `*.tfvars.example`), plan files, crash logs, override files, `.env` files, and macOS files. `.terraform.lock.hcl` is committed on purpose.
- Added Terraform in `infra/`:
  - `versions.tf`: Terraform `~> 1.16.0`, `azurerm` `~> 4.81.0`, `resource_provider_registrations = "none"`. The subscription ID comes from `ARM_SUBSCRIPTION_ID`, never from a file.
  - `variables.tf`: `budget_alert_email` (sensitive, validated), `budget_amount` (default 5), `location` (default `westeurope`).
  - `main.tf`: the monthly subscription budget `budget-monthly-subscription`, with alerts at 20% actual, 100% actual, and 100% forecast. The start date is the first of the current month, computed at apply time; later changes to it are ignored.
  - `outputs.tf`: `budget_id`.
  - `terraform.tfvars.example`, and `.terraform.lock.hcl` with checksums for `darwin_arm64` and `linux_amd64`.
- Checks: `terraform fmt` and `validate` passed; `trivy config` found 0 misconfigurations.
- Applied a saved plan targeted at the budget (`-target` used only for this bootstrap). The billing currency is CHF, so the budget is 5 CHF/month, from 2026-09-01 to 2036-09-01. Current spend: 0.
- The first apply failed with `403 AuthorizationFailed` because the account only had User Access Administrator at root scope. Fixed by granting Owner on the subscription. Recommended follow-up: remove the root-scope role. See the [runbook](docs/runbook.md#terraform-apply-fails-with-403-authorizationfailed).
- The saved plan file contained the alert email in plain text and was deleted after the apply. `infra/terraform.tfstate` exists locally and is gitignored.
- Docs: added [Terraform first run](docs/setup.md#8-terraform-first-run), [Check the budget](docs/runbook.md#check-the-budget), and the Step 2 security measures in [security](docs/security.md).
- Recorded decisions [0005](docs/decisions/0005-subscription-level-budget.md), [0006](docs/decisions/0006-local-terraform-state.md), and [0007](docs/decisions/0007-subscription-id-via-env-var.md).

## 2026-09-29: Step 1: Website

- Added the website in `site/`: `index.html`, `404.html`, `css/style.css`, `favicon.svg`, `robots.txt`, and `staticwebapp.config.json`.
- Plain HTML and CSS: no JavaScript, no inline styles or scripts, no third-party assets. Light and dark mode follow the system setting (`prefers-color-scheme`).
- Security headers in `staticwebapp.config.json`: strict CSP without `unsafe-inline`, HSTS (1 year, `includeSubDomains`), `nosniff`, `Referrer-Policy`, a restrictive `Permissions-Policy`, `X-Frame-Options: DENY`, and `Cross-Origin-Opener-Policy: same-origin`.
- Custom 404 page through `responseOverrides`.
- Still to edit by the user: the intro text, the LinkedIn URL, and the email address (`REPLACE_ME` placeholders). See the [runbook](docs/runbook.md#placeholders-still-to-edit).
- Recorded decisions [0001](docs/decisions/0001-plain-html-no-build.md), [0002](docs/decisions/0002-azure-static-web-apps-free-tier.md), [0003](docs/decisions/0003-dns-at-hostpoint-manual-records.md), and [0004](docs/decisions/0004-strict-csp-no-inline-code.md).

## 2026-09-29: Step 0: Prerequisites and logins

- Already installed: git 2.50.1, terraform 1.16.4 (from `hashicorp/tap`), gh 2.101.0.
- Newly installed with `brew install azure-cli gitleaks trivy`: az 2.90.0, gitleaks 8.30.1, trivy 0.74.0.
- `gh auth login`: done.
- `az login` and `az account show`: pending. The user runs these interactively.
- See [docs/setup.md](docs/setup.md).

## 2026-09-29: Team setup

- Created the agent team: the coordinator (main session), the `deployer` subagent, and the `docs-writer` subagent, defined in `.claude/agents/`. Approved by the user.
