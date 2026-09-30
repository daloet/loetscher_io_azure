# loetscher.io

Personal website hosted as an **Azure Static Web App (Free tier)**. Infrastructure is managed by **Terraform** and deployments run on **GitHub Actions**. Goals: $0/month, secure, beginner-friendly. The user is a beginner, so explain steps and ask before anything outward-facing.

## Team setup
Three agents:
- **Coordinator (main session):** the only agent that talks to the user. Plans the work, delegates it, reviews every result against the security guidelines, reviews every diff before commit, and keeps this file current. Gets **explicit** user approval (e.g. "approve apply") before anything that creates, changes, or deletes cloud resources, pushes to GitHub, or sets secrets. Vague replies like "continue" are not enough; the auto-mode classifier blocks them too.
- **`deployer`** ([.claude/agents/deployer.md](.claude/agents/deployer.md)): writes the site, Terraform, and workflows, and runs CLI commands. Never runs apply, destroy, push, or `gh secret set` without confirmed user approval of that specific action.
- **`docs-writer`** ([.claude/agents/docs-writer.md](.claude/agents/docs-writer.md)): edits Markdown only (not this file). Runs at the end of every step.

## Project structure
```
site/                  plain HTML + CSS, no JS, no build step
  index.html, 404.html, css/style.css, favicon.svg, robots.txt, staticwebapp.config.json
infra/                 Terraform, local state (gitignored)
  versions.tf          Terraform ~> 1.16.0, azurerm ~> 4.81.0; registers only Microsoft.Web
  budget.tf            subscription budget (applied)
  main.tf              RG + SWA + custom domains (www gated by enable_www_domain)
  variables.tf, outputs.tf (default_host_name, dns_records, deployment_token [sensitive], budget_id)
  terraform.tfvars.example, .terraform.lock.hcl (darwin_arm64 + linux_amd64)
  terraform.tfvars     gitignored: budget_alert_email (never print)
.githooks/pre-commit   gitleaks on staged changes (core.hooksPath=.githooks)
.github/workflows/     deploy-site.yml (prod + PR previews), terraform.yml (fmt/validate/trivy on every PR)
.github/dependabot.yml github-actions + terraform, weekly
docs/                  architecture, setup, security, runbook, decisions/ (ADRs 0001–0010)
README.md, CHANGELOG.md
```

## How to run Terraform
```zsh
cd infra
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)   # never stored in files
terraform fmt -recursive && terraform validate && trivy config .
terraform plan -out=x.tfplan      # show the plan, get approval, then: terraform apply x.tfplan && rm x.tfplan
```
- Plan files and `terraform.tfstate` contain sensitive values (the alert email and the **SWA deployment token**). Never print them, and delete plan files after use.
- Redact GUIDs and emails from any output shown to the user (pipe through `sed`).
- Never run `terraform output deployment_token` unpiped. Only use `terraform output -raw deployment_token | gh secret set ...` (with approval).

## Conventions
- Resource group `rg-loetscher-web` in **westeurope**. SWA `swa-loetscher-web` in **eastus2** (westeurope rejected new SWAs: "region not accepting new customers"; see ADR 0008). SKU Free/Free.
- Subscription-level budget `budget-monthly-subscription`: 5 CHF/month, alerts at 20% actual, 100% actual, 100% forecast.
- Terraform and provider versions pinned, and the lock file committed. State is local and never committed.
- GitHub Actions pinned to full commit SHAs with a version comment. Top-level `permissions: contents: read`; widen per job only.
- Trivy in CI is a checksum-verified pinned binary, **not** `aquasecurity/trivy-action` (supply-chain compromise GHSA-69fq-xp46-6x23, March 2026).
- `Azure/static-web-apps-deploy` is pinned to the `v1` branch head (the `v1` tag is from 2021 and lacks `skip_api_build`/`production_branch`).
- No terraform plan or OIDC in CI (local state; the budget needs subscription scope). Optional later, together with a remote backend.
- The site has no inline JS, CSS, or event handlers, and no third-party assets. Security headers live in `site/staticwebapp.config.json`. HSTS keeps `includeSubDomains` (no other subdomains in use).
- Small, focused commits; the coordinator reviews the diff before each commit.

## Status (last updated 2026-09-29)
- [x] Team setup
- [x] Step 0: tools installed; az and gh logged in (GitHub user `daloet`, one Azure subscription "Subscription 1")
- [x] Step 1: website (placeholders still to fill: intro text, LinkedIn URL, email in `site/index.html`)
- [x] Step 2: budget applied
- [~] Step 3: RG, SWA, and apex custom domain `loetscher.io` applied (domain status "Validating"). **Waiting for the user** to create the DNS records at Hostpoint (`terraform output dns_records`: TXT @, ANAME @, CNAME www; remove old A/AAAA @ and www parking records; keep MX). Then: verify with `dig`, set `enable_www_domain = true` in terraform.tfvars, plan, and apply with approval.
- [~] Step 4: prepared locally, **nothing committed or pushed yet**. `git init -b main` done, hook active, workflows and dependabot written and reviewed. Pending user decisions:
  - Git identity: proposed local `user.name "Daniel Loetscher"` + the GitHub noreply email (`<id>+daloet@users.noreply.github.com`, look it up with `gh api user`). Not set yet.
  - Approval for, in order: (a) 5 local commits (gitignore+hook → site → infra → CI → docs), (b) `gh repo create daloet/loetscher.io --public` (no push), (c) `terraform output -raw deployment_token | gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN -R daloet/loetscher.io`, (d) `git push -u origin main` (first deploy), (e) secret scanning, push protection, Dependabot alerts and security updates, (f) branch protection on main: PR required, required check "fmt, validate, trivy", no force push/deletion, 0 approvals, enforce for admins (asked whether the user wants that).
- [ ] Step 5: DNS verification (`dig`, HTTPS on apex + www, `curl -I` headers, securityheaders.com); set loetscher.io as the SWA **default domain** in the portal (Custom domains → Set default) so www and *.azurestaticapps.net redirect to it (portal only, not in Terraform or az CLI); verify with curl.
- [ ] Final: docs-writer final pass; summary including teardown (`terraform destroy`, delete the GitHub secret/repo, remove the Hostpoint records).

## Decisions and facts
- DNS at **Hostpoint**, records edited by hand by the user; no DNS in Terraform. Hostpoint supports ANAME.
- Canonical host: apex `loetscher.io`; www redirects to it (Step 5).
- The www custom domain uses cname-delegation (validated immediately), so it's gated behind `enable_www_domain` (default false).
- The budget alert email only goes into `infra/terraform.tfvars`, never into committed files or docs.
- Billing currency CHF. Free tier: 100 GB/month bandwidth, 2 custom domains, 3 preview environments, no overage billing.
- Azure access: the user's account is Owner on the subscription; the root-scope User Access Administrator was removed.
- `azurerm` registers Microsoft.Web at provider start, i.e. already during `plan` (now registered).
- Tools: az 2.90.0, gitleaks 8.30.1, trivy 0.74.0, terraform 1.16.4 (hashicorp/tap), gh 2.101.0.
