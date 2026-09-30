# loetscher.io

The personal website of Daniel Loetscher.

- **Hosting:** Azure Static Web App `swa-loetscher-web`, Free tier (created in Step 3; no site deployed yet)
- **Infrastructure:** Terraform in `infra/`: the subscription budget (Step 2), the resource group, the Static Web App, and its custom domains (Step 3).
- **Cost guard:** the Free tier has no overage billing, so it cannot incur charges. A subscription budget of 5 CHF/month emails alerts as a backstop (it does not cap spending).
- **Deployments:** GitHub Actions (planned, see Step 4)
- **DNS:** Hostpoint, with records edited by hand. Canonical address: `loetscher.io` ([ADR 0010](docs/decisions/0010-apex-as-canonical-host.md)).
- **Goals:** cost $0/month, be secure, and stay beginner-friendly.

## Status

| Step | What | Status |
|------|------|--------|
| - | Team setup (coordinator, `deployer`, `docs-writer`) | Done |
| 0 | Prerequisites and logins | Done (az and gh logged in) |
| 1 | Website in `site/` | Done (placeholders still to edit) |
| 2 | Budget alert | Done (5 CHF/month, applied 2026-09-29) |
| 3 | Terraform: Static Web App and custom domains | Done (applied 2026-09-29; `www` domain waits for its DNS record) |
| 4 | GitHub repo and CI/CD | Planned |
| 5 | DNS and verification | Planned |

See [CHANGELOG.md](CHANGELOG.md) for details on each step.

## Architecture in short

Plain HTML and CSS files live in `site/`. Terraform created a resource group `rg-loetscher-web` (region `westeurope`) that holds the Static Web App `swa-loetscher-web` (region `eastus2`, see [ADR 0008](docs/decisions/0008-swa-region-eastus2.md)). The Static Web App serves files from Azure's global edge network. When the project is finished, a push to GitHub will start a GitHub Actions workflow that uploads `site/` to the Static Web App. Visitors reach the site at `loetscher.io` through DNS records at Hostpoint; `www.loetscher.io` will redirect there. A subscription budget emails an alert if Azure costs appear.

Full details and a diagram: [docs/architecture.md](docs/architecture.md).

## Repository layout

What exists today:

```
site/                        # the website: plain HTML + CSS, no build step
  index.html                 # home page
  404.html                   # custom "page not found" page
  css/style.css              # all styles (light and dark mode)
  favicon.svg                # browser tab icon
  robots.txt                 # allows search engines to index the site
  staticwebapp.config.json   # Azure SWA config: security headers, custom 404
infra/                       # Terraform
  versions.tf                # pinned Terraform and azurerm versions, provider settings
  variables.tf               # inputs: budget, regions, names, apex_domain, enable_www_domain, tags
  budget.tf                  # the monthly subscription budget and its alerts
  main.tf                    # resource group, Static Web App, custom domains
  outputs.tf                 # default_host_name, dns_records, deployment_token (sensitive), budget_id
  terraform.tfvars.example   # template for your own terraform.tfvars
  .terraform.lock.hcl        # provider checksums (committed on purpose)
docs/                        # documentation
  architecture.md, setup.md, security.md, runbook.md, decisions/
.claude/agents/              # definitions of the deployer and docs-writer agents
.gitignore                   # keeps state, tfvars, plan files, .env, and macOS files out of Git
CLAUDE.md                    # instructions for the coordinator agent
README.md, CHANGELOG.md
```

Local only, never committed (gitignored): `infra/terraform.tfvars` (your real values), `infra/terraform.tfstate` and its backups (Terraform's record of what it created; it also contains the deployment token), and `infra/.terraform/` (downloaded providers). See [security](docs/security.md#gitignore-what-never-goes-into-git).

Planned (not created yet):

```
.github/workflows/           # deploy-site.yml, terraform.yml (optional)
.github/dependabot.yml       # automatic dependency update pull requests
```

## Getting started

1. Install the tools and log in: [docs/setup.md](docs/setup.md).
2. Run Terraform for the first time (creates the budget): [docs/setup.md](docs/setup.md#8-terraform-first-run).
3. Create the Static Web App and custom domains: [docs/setup.md](docs/setup.md#9-static-web-app-and-custom-domains).
4. Edit and preview the site locally: [docs/runbook.md](docs/runbook.md#edit-and-preview-the-site-locally).

## How to deploy changes (planned)

This works once Step 4 is done. Until then the site only exists locally.

1. Edit files in `site/`.
2. Preview them locally (see the [runbook](docs/runbook.md)).
3. Commit and push to the `main` branch:
   ```sh
   git add site/
   git commit -m "Update site"
   git push
   ```
4. GitHub Actions deploys the site automatically.

## How to tear everything down

These steps remove everything the project created. Today steps 1 and 4 apply. Steps 2 and 3 apply once Step 4 (GitHub repo and CI/CD) is done.

1. Delete the Azure resources that Terraform manages (the custom domains, the Static Web App, the resource group, and the budget):
   ```sh
   cd infra
   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   terraform destroy
   ```
   Read the plan it shows, then type `yes` to confirm. Note: this also deletes the budget, so cost alerts stop. The provider registration `Microsoft.Web` stays on the subscription; it is free and harmless.
2. Delete the deployment token secret from GitHub:
   ```sh
   gh secret delete AZURE_STATIC_WEB_APPS_API_TOKEN
   ```
3. Delete the GitHub repository (this cannot be undone):
   ```sh
   gh repo delete <owner>/<repo-name>
   ```
4. In the Hostpoint control panel, delete the DNS records for the Static Web App: `TXT @` (validation token), `ANAME @`, and `CNAME www`. Keep the MX and other mail records.

## Documentation

- [Architecture](docs/architecture.md)
- [Setup from scratch](docs/setup.md)
- [Security](docs/security.md)
- [Runbook](docs/runbook.md)
- [Architecture decision records](docs/decisions/README.md)
- [Changelog](CHANGELOG.md)
