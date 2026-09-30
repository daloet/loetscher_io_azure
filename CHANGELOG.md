# Changelog

One entry per completed step, newest first.

## 2026-09-30: Step 4: GitHub repo and CI/CD

- Repository: public [`daloet/loetscher_io_azure`](https://github.com/daloet/loetscher_io_azure). The user created it on github.com with an "Initial commit"; the local project history was rebased on top of it. The remote uses HTTPS with the `gh` credential helper (`gh auth setup-git`).
- `gh` now logs in with a fine-grained personal access token limited to this repository (Contents, Workflows, Secrets, Administration: read and write), entered with `gh auth login --with-token`. It expires; renew it with the same permissions.
- Git identity is set per repository with the GitHub noreply email, so the real email stays out of the public history.
- Added `.githooks/pre-commit`: runs `gitleaks git --pre-commit --staged` and blocks commits with secrets (or when gitleaks is missing). Each clone enables it with `git config core.hooksPath .githooks`.
- Added `.github/workflows/deploy-site.yml` ("Deploy site"): push to `main` deploys to production; pull requests from this repository get a preview environment (URL posted as a PR comment), deleted when the PR closes; fork and Dependabot PRs are skipped (no secrets); manual runs; concurrency (superseded previews are cancelled). `Azure/static-web-apps-deploy` is pinned to the `v1` branch head, because the `v1` tag is from 2021.
- Added `.github/workflows/terraform.yml` ("Terraform checks"): `fmt -check`, `init -backend=false -lockfile=readonly`, `validate`, and Trivy from a checksum-verified pinned binary. Runs on every PR as the required check `fmt, validate, trivy`. No `plan` and no Azure login ([ADR 0011](docs/decisions/0011-ci-checks-without-plan-or-oidc.md)); Trivy not via `trivy-action` because of the March 2026 supply-chain compromise GHSA-69fq-xp46-6x23 ([ADR 0012](docs/decisions/0012-trivy-pinned-binary.md)).
- All actions pinned to full commit SHAs; top-level `permissions: contents: read`, widened per job only where needed.
- Added `.github/dependabot.yml`: weekly updates for GitHub Actions and Terraform. It ignores `Azure/static-web-apps-deploy` (it would propose a downgrade to the 2021 tag) and major `azurerm` versions; both are updated by hand. Trivy in CI is also bumped by hand. Dependabot opened its first PRs right away; see [Handle Dependabot pull requests](docs/runbook.md#handle-dependabot-pull-requests).
- Set the Actions secret `AZURE_STATIC_WEB_APPS_API_TOKEN` by piping `terraform output -raw deployment_token` into `gh secret set` (never printed).
- Enabled secret scanning, push protection, Dependabot alerts, and Dependabot security updates.
- Branch protection on `main`: PR required (0 approvals, solo developer), required check `fmt, validate, trivy` (branch must be up to date), enforced for admins, linear history, conversation resolution required, no force pushes or deletion. **Every change now goes through a pull request.**
- First production deployment succeeded. All security headers were verified with `curl -I` on `<swa-default-hostname>`, and a missing page returns the custom 404 page with status `404`. The custom domain DNS at Hostpoint is still pending (Step 5).
- Docs: [setup](docs/setup.md) section 6 (PAT login, clone, Git identity, pre-commit hook) and new [section 10](docs/setup.md#10-github-repository-and-cicd); [runbook](docs/runbook.md): [Update the site](docs/runbook.md#update-the-site) via PR, preview troubleshooting, Dependabot PRs, manual updates (SWA action, Trivy, azurerm major), token rotation (now live), PAT renewal; Step 4 measures in [security](docs/security.md#in-place-now-step-4-github-repository-and-cicd); new architecture diagram; README deploy and teardown steps with the correct repository name.
- Recorded decisions [0011](docs/decisions/0011-ci-checks-without-plan-or-oidc.md) and [0012](docs/decisions/0012-trivy-pinned-binary.md); updated [0006](docs/decisions/0006-local-terraform-state.md) to link to 0011.

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
