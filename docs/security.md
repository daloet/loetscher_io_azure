# Security

This page lists the security measures for loetscher.io and **why** each one exists. It separates what is **in place now** (Steps 1 to 3) from what is **planned** for later steps.

## In place now (Step 1: website)

### No inline code and no third-party assets

- The HTML has no inline `<script>` tags, no inline event handlers (such as `onclick=`), and no inline `style=` attributes. All styling lives in `site/css/style.css`.
- The site has no JavaScript at all.
- There are no third-party scripts, fonts, or CDNs. The site uses the system font, and every file is served from loetscher.io itself.
- External links use `rel="noopener noreferrer"`.

**Why:** Inline code is the usual way injected (malicious) code runs in a page. Without any inline code, the site can use a strict Content Security Policy (below). Loading nothing from other servers means no other company can change what the site runs, and visitors are not tracked by them. `noopener noreferrer` stops a linked page from controlling this tab and from seeing which page the visitor came from. See [ADR 0004](decisions/0004-strict-csp-no-inline-code.md).

### Security headers

**Security headers** are instructions the server sends with every page, telling the browser how to protect the visitor. They are set in `site/staticwebapp.config.json` under `globalHeaders`, so Azure adds them to every response. They take effect once the site is deployed (Step 4).

| Header | Value (short) | Why |
|--------|---------------|-----|
| `Content-Security-Policy` (CSP) | `default-src 'self'`, no `unsafe-inline`, `object-src 'none'`, `frame-ancestors 'none'`, `upgrade-insecure-requests` | A **CSP** is an allow-list of where the page may load scripts, styles, images, and so on. Here: only from loetscher.io itself. Injected inline code is blocked. |
| `Strict-Transport-Security` (HSTS) | `max-age=31536000; includeSubDomains` | Tells browsers to use HTTPS only, for 1 year. This stops attackers from downgrading a visitor to insecure HTTP. |
| `X-Content-Type-Options` | `nosniff` | Stops the browser from guessing a file's type, which could turn a harmless file into a running script. |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Other sites only see `https://loetscher.io`, not the full page address, when a visitor follows a link. |
| `Permissions-Policy` | camera, microphone, geolocation, payment, USB, and more all disabled | The site needs none of these browser features, so nothing can ever ask for them. |
| `X-Frame-Options` | `DENY` | Stops other sites from showing this site in a frame (protects against **clickjacking**, where a hidden frame tricks users into clicking). Older browsers use this; newer ones use CSP `frame-ancestors`. |
| `Cross-Origin-Opener-Policy` | `same-origin` | Isolates this site's browser window from windows opened by other sites. |

#### Warning: HSTS `includeSubDomains`

`includeSubDomains` means browsers that visit loetscher.io will also insist on HTTPS for **every** subdomain (for example `mail.loetscher.io` or `webmail.loetscher.io`) for 1 year.

**Checked (2026-09-29):** the user confirmed that no other loetscher.io subdomains are in use. The only web subdomain is `www.loetscher.io`, which the Static Web App serves over HTTPS. So `includeSubDomains` stays.

If you add a subdomain later:

- It must serve a valid HTTPS certificate. If it only works over plain HTTP, browsers that have seen the header will refuse to open it.
- Once browsers have seen the header, it cannot be taken back for up to 1 year.

### Custom 404 page

`responseOverrides` in `staticwebapp.config.json` shows `404.html` for missing pages, with the correct `404` status code. The page is marked `noindex` so search engines skip it. **Why:** A clean error page reveals nothing about the server.

## In place now (Step 2: Terraform and budget)

### .gitignore: what never goes into Git

The root `.gitignore` file lists files Git must never track:

| Pattern | What it is |
|---------|------------|
| `*.tfstate`, `*.tfstate.*` | Terraform state and its backups |
| `**/.terraform/*` | Downloaded providers (large, rebuilt by `terraform init`) |
| `*.tfvars`, `*.tfvars.json` (except `*.tfvars.example`) | Your real variable values, such as the alert email |
| `*.tfplan`, `tfplan` | Saved plan files |
| `crash.log`, override files, `.terraformrc` | Terraform debug output and local CLI settings |
| `.env`, `.env.*` | Environment files that often hold secrets |
| `.DS_Store`, `._*`, and similar | macOS clutter |

`.terraform.lock.hcl` is **intentionally committed** (see version pinning below).

**Why:** Anything committed stays in Git history, even after you delete the file later. It is far easier to never commit a secret than to remove it afterwards.

### Secrets in tfvars, state, and plan files

- The budget alert email is personal data. It lives only in `infra/terraform.tfvars`, which is gitignored. The committed `infra/terraform.tfvars.example` holds only a dummy address.
- The variable `budget_alert_email` is marked `sensitive`, so Terraform hides it (`(sensitive value)`) in plan and apply output on screen. It also has a validation rule, so a typo is caught before anything is sent to Azure.
- **Plan files and state still contain sensitive values in plain text.** `sensitive` only hides values on screen. A saved plan file (`terraform plan -out=tfplan`) and the state file store them readably. In Step 2 the saved plan contained the alert email in plain text; it was deleted right after the apply. Both plan files and state are gitignored.

**Why:** Hiding values on screen prevents leaks through screenshots and logs. Keeping the files out of Git prevents leaks through the repository. Deleting plan files after use leaves fewer copies lying around.

### Local Terraform state

The **state file** (`infra/terraform.tfstate`) is Terraform's record of what it created in Azure. It is kept on the local Mac only. See [ADR 0006](decisions/0006-local-terraform-state.md).

Risks and how to handle them:

- **It contains secrets.** It holds the alert email and, since Step 3, the Static Web App **deployment token** (the secret that allows uploading the site) in plain text. The file is gitignored. Never commit it, never share it, never paste it anywhere.
- **No backup.** If the file is lost, Terraform no longer knows about the budget, the resource group, the Static Web App, or the custom domains. Keep a private backup, for example in an encrypted folder or password manager, and not in a synced public folder. Update the backup after each apply.
- **No locking.** Only one person or process should run Terraform at a time. That is fine for a one-person project.
- **Later option:** move to a **remote backend** (state stored in a service instead of a local file), such as an Azure Storage account or the HCP Terraform free tier. That gives locking, backups, and encryption. Not planned yet.

### Subscription ID not stored in files

The Azure subscription ID is never written into any file. Terraform reads it from the `ARM_SUBSCRIPTION_ID` environment variable, which you set per Terminal session with `export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)`. See [ADR 0007](decisions/0007-subscription-id-via-env-var.md).

Note: the output `budget_id` and Terraform's plan output contain the full resource ID, which includes the subscription ID. Don't paste them into issues, chats, or docs.

**Why:** A subscription ID is not a password, but it is an identifier attackers can use for targeting and phishing. Keeping it out of the repository costs nothing.

### Version pinning

- `infra/versions.tf` pins Terraform to `~> 1.16.0` and the `azurerm` provider to `~> 4.81.0`. The `~>` operator allows only patch updates (for example 4.81.1), not new minor versions.
- `infra/.terraform.lock.hcl` is committed. It records the exact provider version and its checksums for `darwin_arm64` (Apple Silicon Macs) and `linux_amd64` (planned GitHub Actions runners).
- The provider setting `resource_provider_registrations = "none"` stops Terraform from registering about 20 Azure **resource providers** (the service namespaces a subscription may use) automatically. Since Step 3, `resource_providers_to_register = ["Microsoft.Web"]` registers only the one the project needs. This happens when the provider starts, so already during `terraform plan`, not only on apply.

**Why:** Every run uses the same tested code. The lock file makes `terraform init` refuse a provider download whose checksum does not match, which protects against tampered downloads. Registering nothing by default keeps the subscription's footprint small.

### trivy config scan

Before each apply, `trivy config` scans `infra/`. In Step 2 it found 0 misconfigurations. `terraform fmt` and `terraform validate` also passed. This check runs before every apply (see [setup](setup.md#8-terraform-first-run)).

**Why:** trivy finds insecure Terraform settings before they reach Azure, when they are cheap to fix.

### Least privilege for the Azure account

**Least privilege** means every account gets only the permissions it needs. The first apply failed with `403 AuthorizationFailed`, because the logged-in account only had **User Access Administrator** at root scope `/` (a very powerful role that can grant any access in the whole tenant) and no role on the subscription. The account was then given **Owner** on the subscription.

**Done (2026-09-29):** the user removed the root-scope User Access Administrator, which was no longer needed. How it is done (for reference):

1. In the Azure portal, open **Microsoft Entra ID** > **Properties**.
2. Set **Access management for Azure resources** to **No**.
3. Select **Save**.

Check your roles with:

```sh
az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" --all -o table
```

**Why:** A root-scope User Access Administrator can give itself access to everything. If that account were ever compromised, the damage would not be limited to this project.

### Budget alerts

A subscription budget of 5 CHF/month emails alerts at 20% actual, 100% actual, and 100% forecast cost. **Why:** it detects unexpected costs early, for example from a misconfiguration or a misused account. It does **not** cap spending. See [ADR 0005](decisions/0005-subscription-level-budget.md).

## In place now (Step 3: Static Web App)

### Free tier only, no overage billing

The Static Web App uses `sku_tier = "Free"` and `sku_size = "Free"`. Free limits: 100 GB bandwidth per month, 2 custom domains, 3 preview environments. The Free plan has no **overage billing** (charges for use above the quota), so heavy traffic cannot create a bill. `infra/main.tf` warns never to switch to `Standard` without checking the cost first.

**Why:** a public website can be hit by unexpected traffic, including attacks. On Free, the worst case is that the site stops serving until the quota resets, not a bill. The budget alerts remain as a backstop for anything else in the subscription.

### Minimal Static Web App settings

- No app settings, no managed identity, no basic auth, and no backend. The site is purely static.
- `configuration_file_changes_enabled = true`, so the security headers in `staticwebapp.config.json` are applied on deploy.
- Public network access is on (it is a public website).
- Preview environments are on: pull requests get a temporary public preview URL (up to 3 at a time).

**Why:** every feature that is not there cannot be misconfigured. The config file must stay enabled because the security headers depend on it. Note that preview URLs are public, so don't put anything private in a pull request.

### Deployment token handling

The **deployment token** (API key) lets anyone who has it upload content to the site.

- It is the Terraform output `deployment_token`, marked `sensitive`, so Terraform hides it on screen.
- It is stored in plain text in the local `infra/terraform.tfstate` (gitignored). Don't share the state file.
- It must never be printed. In Step 4 it will be piped straight into a GitHub secret (with user approval):
  ```sh
  terraform output -raw deployment_token | gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN
  ```
- Rotation is planned for Step 4. See [Rotate the deployment token](runbook.md#rotate-the-deployment-token-planned-step-4).

**Why:** whoever holds the token can replace the website. Keeping it off screens, out of files, and out of Git history makes a leak unlikely; rotation limits the damage if one happens.

### DNS validation token is public on purpose

The `TXT` validation token (`<txt-validation-token>`) is shown by `terraform output dns_records`. It is not hidden, because it is published in public DNS anyway. It only proves ownership of the domain for this one Static Web App.

## Planned

These measures are part of later steps and are **not in place yet**.

| Measure | Step | Why |
|---------|------|-----|
| **Deployment token in a GitHub secret:** piped straight from Terraform into `AZURE_STATIC_WEB_APPS_API_TOKEN`, never printed. Rotation steps in the runbook. | 4 | Secrets must never end up on screen, in files, or in Git history. |
| **gitleaks pre-commit hook** | 4 | Scans every commit for secrets and blocks it if one is found. A **pre-commit hook** is a script Git runs before each commit. |
| **GitHub secret scanning and push protection** | 4 | GitHub checks pushed code for known secret formats and blocks the push. A second safety net after gitleaks. |
| **Least-privilege workflow permissions** (`permissions: contents: read` at the top level) | 4 | If a workflow is ever compromised, it can do as little damage as possible. |
| **SHA-pinned GitHub Actions** (full 40-character commit SHA plus a version comment) | 4 | A tag like `v4` can be moved to different code by whoever controls it. A commit SHA cannot. |
| **Dependabot** | 4 | Opens pull requests when pinned actions or providers have updates, so pinning does not mean falling behind on fixes. |
| **Branch protection on `main`** | 4 | Stops force-pushes and accidental deletion of the branch that deploys the site. |
| **Remote Terraform backend** (optional) | Not scheduled | Locking, backups, and encryption for the state file. See [ADR 0006](decisions/0006-local-terraform-state.md). |

## Related

- [ADR 0004: Strict CSP, no inline code](decisions/0004-strict-csp-no-inline-code.md)
- [ADR 0005: Subscription-level budget](decisions/0005-subscription-level-budget.md)
- [ADR 0006: Local Terraform state](decisions/0006-local-terraform-state.md)
- [ADR 0007: Subscription ID via environment variable](decisions/0007-subscription-id-via-env-var.md)
- [ADR 0010: Apex loetscher.io as the canonical host](decisions/0010-apex-as-canonical-host.md)
- [Runbook](runbook.md)
