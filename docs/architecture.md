# Architecture

This page describes the architecture of loetscher.io. Today these parts exist: the website files in `site/` (Step 1), the subscription budget (Step 2), and the resource group, Static Web App, and apex custom domain (Step 3), all created by Terraform from `infra/`. The GitHub repository and workflows (Step 4) and the final DNS checks and `www` redirect (Step 5) are planned. See the status table in the [README](../README.md#status).

## Diagram

```mermaid
flowchart LR
    dev["Developer Mac<br/>(edits site/)"] -->|"git push (planned, Step 4)"| repo["GitHub repository"]
    repo -->|triggers| gha["GitHub Actions<br/>deploy-site.yml (planned)"]
    gha -->|"uploads site/<br/>(uses deployment token)"| swa

    tf["Terraform<br/>(runs locally, local state)"] -->|creates| rg
    tf -->|creates| swa
    tf -->|creates| domains
    tf -->|creates| budget

    subgraph sub["Azure subscription"]
        subgraph rg["Resource group rg-loetscher-web (westeurope)"]
            swa["Static Web App swa-loetscher-web<br/>Free tier, region eastus2<br/>(metadata only)"]
            domains["Custom domains<br/>loetscher.io (TXT validation)<br/>www.loetscher.io (planned, CNAME validation)"]
        end
        budget["Subscription budget<br/>budget-monthly-subscription<br/>5 CHF per month"]
    end

    domains --- swa
    swa -->|serves content from| edge["Azure global edge network"]
    budget -->|email alerts| mail["Budget alert inbox"]

    visitor["Visitor's browser"] -->|"1. DNS lookup"| dns["Hostpoint DNS (manual)<br/>TXT @, ANAME @, CNAME www"]
    dns -->|"2. points to the SWA default hostname"| edge
    visitor -->|"3. HTTPS request to loetscher.io"| edge
```

## Components

| Component | What it is | Status |
|-----------|-----------|--------|
| Website (`site/`) | Plain HTML and CSS files. No build step, no JavaScript. | Done (Step 1); not deployed yet |
| Subscription budget | `budget-monthly-subscription` (in `infra/budget.tf`): a monthly cost threshold of 5 CHF (the billing currency) on the whole subscription, starting 2026-09-01. It sends emails at 20% of actual cost (1 CHF), 100% of actual cost, and 100% of forecast cost. It only warns; it does **not** stop or cap spending. See [ADR 0005](decisions/0005-subscription-level-budget.md). | Live (Step 2) |
| Resource group `rg-loetscher-web` | A folder in Azure that holds the project's resources. Region `westeurope` (variable `location`). | Live (Step 3) |
| Static Web App `swa-loetscher-web` | Azure's service for hosting static files, on the **Free** plan. It serves the site over HTTPS and provides free TLS certificates for custom domains. Its region is `eastus2` (variable `static_web_app_location`), because `westeurope` did not accept new Static Web Apps ([ADR 0008](decisions/0008-swa-region-eastus2.md)). The region only holds metadata; content is served from Azure's global **edge** network (servers close to visitors worldwide). Preview environments and `staticwebapp.config.json` changes are enabled. It has an auto-generated **default hostname** of the form `<random-name>.azurestaticapps.net` (called `<swa-default-hostname>` in these docs). | Live (Step 3) |
| Free tier limits | 100 GB bandwidth per month, 2 custom domains, 3 preview environments. The Free plan has no **overage billing** (charges for use above the quota), so it cannot incur costs. The budget is the backstop. | Applies since Step 3 |
| Terraform | A tool that creates cloud resources from code files in `infra/`. It runs on the developer's Mac and signs in through the Azure CLI login. The subscription ID comes from the `ARM_SUBSCRIPTION_ID` environment variable, not from a file ([ADR 0007](decisions/0007-subscription-id-via-env-var.md)). Its **state file** (a record of what it created) stays on the local machine and is never committed ([ADR 0006](decisions/0006-local-terraform-state.md)). The provider registers only the `Microsoft.Web` **resource provider** (the Azure service namespace that Static Web Apps belong to). | In use since Step 2 |
| Custom domain `loetscher.io` | The apex (bare) domain and the **canonical host** ([ADR 0010](decisions/0010-apex-as-canonical-host.md)). Validated with a `TXT` record (`dns-txt-token`). Terraform does not wait for validation; Azure checks DNS in the background. | Created (Step 3); valid once the DNS records exist |
| Custom domain `www.loetscher.io` | Validated with `cname-delegation`, which Azure checks immediately. Therefore it is only created when `enable_www_domain = true`, after the `CNAME` exists ([ADR 0009](decisions/0009-two-step-custom-domain-rollout.md)). Will redirect to `loetscher.io` via the portal's "default domain" setting. | Planned (after the DNS records; redirect in Step 5) |
| Hostpoint DNS | The DNS provider for `loetscher.io`. **DNS** translates a name like `loetscher.io` into the address of a server. Records (`TXT @`, `ANAME @`, `CNAME www`) are edited by hand in the Hostpoint control panel ([ADR 0003](decisions/0003-dns-at-hostpoint-manual-records.md)). See [DNS records at Hostpoint](runbook.md#dns-records-at-hostpoint). | Manual; checks in Step 5 |
| Deployment token | A secret from the Static Web App that lets the workflow upload files. Terraform exposes it as the sensitive output `deployment_token`. It will be stored as the GitHub secret `AZURE_STATIC_WEB_APPS_API_TOKEN`. | Exists (Step 3); GitHub secret planned (Step 4) |
| GitHub repository | Stores the code and docs. | Planned (Step 4) |
| GitHub Actions | GitHub's automation service. A workflow uploads `site/` to Azure on every push to `main`. | Planned (Step 4) |

## Terraform outputs

| Output | What it shows |
|--------|---------------|
| `default_host_name` | The Static Web App's generated hostname, `<swa-default-hostname>`. |
| `dns_records` | The three records to create at Hostpoint: `TXT @` with `<txt-validation-token>`, `ANAME @` to `<swa-default-hostname>`, `CNAME www` to `<swa-default-hostname>`. |
| `deployment_token` | Sensitive. Never print it. It will be piped straight into a GitHub secret in Step 4. |
| `budget_id` | The budget's resource ID (contains the subscription ID; don't share it). |

## How the pieces connect

1. **Build the infrastructure (once).** Terraform runs on the developer's Mac. It created the budget first, on its own (Step 2). In Step 3 it created the resource group, the Static Web App, and the apex custom domain.
2. **Connect DNS.** The user creates the records from `terraform output dns_records` at Hostpoint. Azure then validates `loetscher.io`. After that, `enable_www_domain = true` adds `www.loetscher.io` ([ADR 0009](decisions/0009-two-step-custom-domain-rollout.md)).
3. **Connect GitHub (planned, Step 4).** The Static Web App's deployment token is piped straight from Terraform into a GitHub secret, without being printed.
4. **Deploy (every change, planned).** A push to `main` triggers GitHub Actions. The workflow uploads `site/` to the Static Web App.
5. **Serve visitors.** A visitor's browser asks Hostpoint DNS where `loetscher.io` lives. The `ANAME` record points to the Static Web App's default hostname. The browser loads the site over HTTPS from Azure's edge. The security headers from `site/staticwebapp.config.json` are added to every response. Requests to `www.loetscher.io` will redirect to `loetscher.io` (planned, Step 5).
6. **Watch costs.** The Free plan cannot incur charges. If Azure costs ever appear anyway, the budget sends an email alert. See [Check the budget](runbook.md#check-the-budget).

## Related decisions

- [0001: Plain HTML, no build step](decisions/0001-plain-html-no-build.md)
- [0002: Azure Static Web Apps Free tier](decisions/0002-azure-static-web-apps-free-tier.md)
- [0003: DNS at Hostpoint with manual records](decisions/0003-dns-at-hostpoint-manual-records.md)
- [0004: Strict CSP, no inline code](decisions/0004-strict-csp-no-inline-code.md)
- [0005: Subscription-level budget](decisions/0005-subscription-level-budget.md)
- [0006: Local Terraform state](decisions/0006-local-terraform-state.md)
- [0007: Subscription ID via environment variable](decisions/0007-subscription-id-via-env-var.md)
- [0008: Static Web App region eastus2](decisions/0008-swa-region-eastus2.md)
- [0009: Two-step custom domain rollout](decisions/0009-two-step-custom-domain-rollout.md)
- [0010: Apex loetscher.io as the canonical host](decisions/0010-apex-as-canonical-host.md)
