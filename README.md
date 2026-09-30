# loetscher.io

The personal website of Daniel Loetscher.

- **Repository:** [`daloet/loetscher_io_azure`](https://github.com/daloet/loetscher_io_azure) on GitHub (public)
- **Hosting:** Azure Static Web App `swa-loetscher-web`, Free tier. The site is deployed and reachable on its default `*.azurestaticapps.net` hostname; `loetscher.io` follows once DNS is done (Step 5).
- **Infrastructure:** Terraform in `infra/`: the subscription budget (Step 2), the resource group, the Static Web App, and its custom domains (Step 3).
- **Cost guard:** the Free tier has no overage billing, so it cannot incur charges. A subscription budget of 5 CHF/month emails alerts as a backstop (it does not cap spending).
- **Deployments:** GitHub Actions. Every change goes through a pull request with a preview; merging to `main` deploys to production.
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
| 4 | GitHub repo and CI/CD | Done (2026-09-30; first production deploy succeeded) |
| 5 | DNS and verification | Planned |

See [CHANGELOG.md](CHANGELOG.md) for details on each step.

## Architecture in short

Plain HTML and CSS files live in `site/`. Terraform created a resource group `rg-loetscher-web` (region `westeurope`) that holds the Static Web App `swa-loetscher-web` (region `eastus2`, see [ADR 0008](docs/decisions/0008-swa-region-eastus2.md)). The Static Web App serves files from Azure's global edge network. Changes go through pull requests on GitHub: a GitHub Actions workflow checks the Terraform code on every pull request, publishes a preview of `site/`, and deploys `site/` to production once the pull request is merged into `main`. Dependabot proposes updates weekly. Visitors will reach the site at `loetscher.io` through DNS records at Hostpoint (Step 5); `www.loetscher.io` will redirect there. A subscription budget emails an alert if Azure costs appear.

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
.github/
  workflows/deploy-site.yml  # deploys site/: PR previews and production on main
  workflows/terraform.yml    # fmt, validate, trivy on every pull request (required check)
  dependabot.yml             # weekly update PRs for actions and the azurerm provider
.githooks/pre-commit         # gitleaks secret scan before every commit
docs/                        # documentation
  architecture.md, setup.md, security.md, runbook.md, decisions/
.claude/agents/              # definitions of the deployer and docs-writer agents
.gitignore                   # keeps state, tfvars, plan files, .env, and macOS files out of Git
CLAUDE.md                    # instructions for the coordinator agent
README.md, CHANGELOG.md
```

Local only, never committed (gitignored): `infra/terraform.tfvars` (your real values), `infra/terraform.tfstate` and its backups (Terraform's record of what it created; it also contains the deployment token), and `infra/.terraform/` (downloaded providers). See [security](docs/security.md#gitignore-what-never-goes-into-git).

## Getting started

1. Install the tools, log in, clone the repository, and turn on the pre-commit hook: [docs/setup.md](docs/setup.md).
2. Run Terraform for the first time (creates the budget): [docs/setup.md](docs/setup.md#8-terraform-first-run).
3. Create the Static Web App and custom domains: [docs/setup.md](docs/setup.md#9-static-web-app-and-custom-domains).
4. Connect GitHub (secret, security settings, branch protection): [docs/setup.md](docs/setup.md#10-github-repository-and-cicd).
5. Edit and preview the site locally: [docs/runbook.md](docs/runbook.md#edit-and-preview-the-site-locally).

## How to deploy changes

`main` is protected, so every change goes through a pull request. In short:

```sh
git switch main && git pull
git switch -c my-change
# edit files in site/, preview locally
git add site/
git commit -m "Update site"          # the gitleaks hook runs here
git push -u origin my-change
gh pr create --fill                  # checks run; a preview URL is posted on the PR
gh pr merge --squash --delete-branch # after checking the preview
git switch main && git pull
```

Merging deploys the site to production automatically. Step-by-step explanation, troubleshooting, and Dependabot PRs: [Update the site](docs/runbook.md#update-the-site).

## How to tear everything down

These steps remove everything the project created.

1. Delete the Azure resources that Terraform manages (the custom domains, the Static Web App, the resource group, and the budget):
   ```sh
   cd infra
   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   terraform destroy
   ```
   Read the plan it shows, then type `yes` to confirm. Note: this also deletes the budget, so cost alerts stop. The provider registration `Microsoft.Web` stays on the subscription; it is free and harmless.
2. Delete the deployment token secret from GitHub (the token itself already stopped working when the Static Web App was deleted):
   ```sh
   gh secret delete AZURE_STATIC_WEB_APPS_API_TOKEN -R daloet/loetscher_io_azure
   ```
3. Delete the GitHub repository (this cannot be undone). `gh` needs the `delete_repo` right for this; the fine-grained token from setup doesn't have it, so either delete the repository in the browser (**Settings** > **General** > **Danger Zone** > **Delete this repository**), or run:
   ```sh
   gh auth refresh -h github.com -s delete_repo   # only works for a browser (OAuth) login
   gh repo delete daloet/loetscher_io_azure
   ```
4. Delete the fine-grained access token on github.com (**Settings** > **Developer settings** > **Personal access tokens** > **Fine-grained tokens**), and log `gh` out: `gh auth logout`.
5. In the Hostpoint control panel, delete the DNS records for the Static Web App: `TXT @` (validation token), `ANAME @`, and `CNAME www`. Keep the MX and other mail records.

## Documentation

- [Architecture](docs/architecture.md)
- [Setup from scratch](docs/setup.md)
- [Security](docs/security.md)
- [Runbook](docs/runbook.md)
- [Architecture decision records](docs/decisions/README.md)
- [Changelog](CHANGELOG.md)
