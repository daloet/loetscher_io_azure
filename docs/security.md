# Security

This page lists the security measures for loetscher.io and **why** each one exists. It separates what is **in place now** (Steps 1 to 4) from what is **optional** for later.

## In place now (Step 1: website)

### No inline code and no third-party assets

- The HTML has no inline `<script>` tags, no inline event handlers (such as `onclick=`), and no inline `style=` attributes. All styling lives in `site/css/style.css`.
- The site has no JavaScript at all.
- There are no third-party scripts, fonts, or CDNs. The site uses the system font, and every file is served from loetscher.io itself.
- External links use `rel="noopener noreferrer"`.

**Why:** Inline code is the usual way injected (malicious) code runs in a page. Without any inline code, the site can use a strict Content Security Policy (below). Loading nothing from other servers means no other company can change what the site runs, and visitors are not tracked by them. `noopener noreferrer` stops a linked page from controlling this tab and from seeing which page the visitor came from. See [ADR 0004](decisions/0004-strict-csp-no-inline-code.md).

### Security headers

**Security headers** are instructions the server sends with every page, telling the browser how to protect the visitor. They are set in `site/staticwebapp.config.json` under `globalHeaders`, so Azure adds them to every response. **Verified (2026-09-30):** after the first deployment, `curl -I` on `https://<swa-default-hostname>/` showed all the headers below, and a missing page returned the custom 404 page with status `404`. How to check: [Check the live site](runbook.md#check-the-live-site). They will be checked again on `loetscher.io` in Step 5.

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
- `infra/.terraform.lock.hcl` is committed. It records the exact provider version and its checksums for `darwin_arm64` (Apple Silicon Macs) and `linux_amd64` (GitHub Actions runners). CI runs `terraform init -lockfile=readonly`, so it fails instead of silently changing the lock file.
- The provider setting `resource_provider_registrations = "none"` stops Terraform from registering about 20 Azure **resource providers** (the service namespaces a subscription may use) automatically. Since Step 3, `resource_providers_to_register = ["Microsoft.Web"]` registers only the one the project needs. This happens when the provider starts, so already during `terraform plan`, not only on apply.

**Why:** Every run uses the same tested code. The lock file makes `terraform init` refuse a provider download whose checksum does not match, which protects against tampered downloads. Registering nothing by default keeps the subscription's footprint small.

### trivy config scan

Before each apply, `trivy config` scans `infra/`. In Step 2 it found 0 misconfigurations. `terraform fmt` and `terraform validate` also passed. This check runs before every apply (see [setup](setup.md#8-terraform-first-run)). Since Step 4 it also runs in CI on every pull request (see [Terraform checks in CI](#terraform-checks-in-ci)).

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
- It is never printed. In Step 4 it was piped straight into the GitHub secret `AZURE_STATIC_WEB_APPS_API_TOKEN` (with user approval):
  ```sh
  terraform output -raw deployment_token | gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN -R daloet/loetscher_io_azure
  ```
- GitHub hides secret values in workflow logs and never shows them again, not even to the repository owner.
- If it may have leaked, rotate it: see [Rotate the deployment token](runbook.md#rotate-the-deployment-token).

**Why:** whoever holds the token can replace the website. Keeping it off screens, out of files, and out of Git history makes a leak unlikely; rotation limits the damage if one happens.

### DNS validation token is public on purpose

The `TXT` validation token (`<txt-validation-token>`) is shown by `terraform output dns_records`. It is not hidden, because it is published in public DNS anyway. It only proves ownership of the domain for this one Static Web App.

## In place now (Step 4: GitHub repository and CI/CD)

The repository is the public `daloet/loetscher_io_azure`. **CI/CD** (continuous integration and continuous deployment) means GitHub Actions checks every change and deploys the site automatically.

### gitleaks pre-commit hook

`.githooks/pre-commit` runs `gitleaks git --pre-commit --staged` before every commit. A **pre-commit hook** is a script Git runs before each commit. If gitleaks finds something that looks like a secret in the staged changes, the commit is blocked (findings are shown redacted). If gitleaks is not installed, the hook blocks the commit too, instead of silently skipping the check. Each clone must turn it on once with `git config core.hooksPath .githooks` (see [setup](setup.md#turn-on-the-pre-commit-hook)).

**Why:** the cheapest place to stop a secret is on your own Mac, before it is in any commit.

### GitHub secret scanning and push protection

Both are enabled on the repository. **Secret scanning** checks the repository for known secret formats (such as cloud keys and tokens). **Push protection** blocks a `git push` that contains one.

**Why:** a second safety net after gitleaks, run by GitHub on its side. It also catches secrets committed on a clone where the hook was not turned on.

### Git identity with a noreply email

Commits use GitHub's noreply address (`<id>+<user>@users.noreply.github.com`), set per repository (see [setup](setup.md#set-your-git-identity-for-this-repository)).

**Why:** commit authors are public in a public repository. The noreply address keeps the real email out of the history, where it could be collected by spammers.

### GitHub CLI login with a fine-grained token

`gh` and `git push` use a **fine-grained personal access token (PAT)** that only works for `daloet/loetscher_io_azure`, with Contents, Workflows, Secrets, and Administration set to read and write. It has an expiry date. It is entered with `gh auth login --with-token` and stored in the macOS keychain; it is never pasted into chats or files. The remote uses HTTPS with the `gh` credential helper (`gh auth setup-git`).

**Why:** a token limited to one repository and a few permissions can do far less damage if it leaks than a classic token for the whole account. The expiry date limits how long a leaked token stays useful.

### Least-privilege workflow permissions

Each workflow sets `permissions: contents: read` at the top level, so the automatic `GITHUB_TOKEN` can only read the code. Jobs widen this only where needed:

- `Build and deploy` adds `pull-requests: write`, only so the preview URL can be posted as a PR comment.
- `Close preview environment` has `permissions: {}` (nothing), because it only talks to Azure.
- `actions/checkout` runs with `persist-credentials: false`, so the token is not left on the runner's disk for later steps.
- Every job has a `timeout-minutes`.

**Why:** if a workflow or an action is ever compromised, it can do as little as possible.

### Secrets only where they are needed

- The deployment token is used only by the deploy workflow. The Terraform checks workflow has no secrets and no Azure login at all ([ADR 0011](decisions/0011-ci-checks-without-plan-or-oidc.md)).
- Pull requests from **forks** (copies of the repository owned by someone else) and from Dependabot get no repository secrets from GitHub. The deploy workflow skips them on purpose (`head.repo.full_name == github.repository` and author is not `dependabot[bot]`), so they get no preview. The required check still runs on them.
- Only pushes to `main` (or a manual run on `main`) deploy to production. The action's `production_branch: "main"` makes sure anything else can only become a preview.

**Why:** a token that is never handed to a job cannot leak from it.

### SHA-pinned GitHub Actions

Every action is pinned to a full 40-character commit SHA, with the version in a comment, for example `actions/checkout@<sha> # v5.1.0`.

- `Azure/static-web-apps-deploy` is pinned to the head of its `v1` **branch**, because its only `v1` tag is from 2021 and lacks inputs the workflow needs. It is updated by hand ([runbook](runbook.md#update-azurestatic-web-apps-deploy-by-hand)).

**Why:** a tag like `v4` can be moved to different code by whoever controls it. A commit SHA cannot.

### Trivy as a checksum-verified binary

CI installs Trivy from a pinned release file and checks its SHA-256 checksum before running it, instead of using `aquasecurity/trivy-action`. That action was hit by a supply-chain compromise in March 2026 (GHSA-69fq-xp46-6x23). See [ADR 0012](decisions/0012-trivy-pinned-binary.md).

**Why:** the workflow only runs the exact file that was reviewed.

### Terraform checks in CI

`.github/workflows/terraform.yml` runs on every pull request: `terraform fmt -check`, `terraform init -backend=false -lockfile=readonly`, `terraform validate`, and `trivy config` (any finding fails). It does not run `plan` and does not log in to Azure ([ADR 0011](decisions/0011-ci-checks-without-plan-or-oidc.md)).

**Why:** insecure or broken Terraform code is caught before it can be merged.

### Dependabot

`.github/dependabot.yml` checks weekly for new versions of the pinned GitHub Actions and of the `azurerm` provider and opens pull requests. It skips `Azure/static-web-apps-deploy` (it would propose a downgrade to the 2021 tag) and major `azurerm` versions (they can break things and need a local plan first). **Dependabot alerts** and **Dependabot security updates** are also enabled on the repository. See [Handle Dependabot pull requests](runbook.md#handle-dependabot-pull-requests).

**Why:** pinning should not mean falling behind on security fixes. Dependabot proposes updates; you still review and merge them.

### Branch protection on main

`main` is the branch that deploys to production. Its protection rules:

| Rule | What it means |
|------|---------------|
| Pull request required (0 approvals) | Nobody can push to `main` directly; every change goes through a PR. No approval is needed, because this is a one-person project. |
| Required status check `fmt, validate, trivy`, strict | The Terraform checks must pass, and the branch must be up to date with `main` before merging. |
| Enforced for admins | The rules apply to the repository owner too. |
| Linear history | No merge commits; use squash or rebase merges. |
| Conversation resolution required | All review comments must be resolved before merging. |
| No force pushes, no deletion | `main`'s history cannot be rewritten, and the branch cannot be deleted. |

**Why:** every change gets the automatic checks and a preview before it goes live, and nobody (including a stolen token) can quietly rewrite what was deployed. The everyday workflow: [Update the site](runbook.md#update-the-site).

## Optional (not scheduled)

| Measure | Why |
|---------|-----|
| **Remote Terraform backend** | Locking, backups, and encryption for the state file. See [ADR 0006](decisions/0006-local-terraform-state.md). |
| **`terraform plan` in CI with OIDC** | Would show a plan on every PR, without storing Azure passwords in GitHub. Needs a remote backend first. See [ADR 0011](decisions/0011-ci-checks-without-plan-or-oidc.md). |

## Related

- [ADR 0004: Strict CSP, no inline code](decisions/0004-strict-csp-no-inline-code.md)
- [ADR 0005: Subscription-level budget](decisions/0005-subscription-level-budget.md)
- [ADR 0006: Local Terraform state](decisions/0006-local-terraform-state.md)
- [ADR 0007: Subscription ID via environment variable](decisions/0007-subscription-id-via-env-var.md)
- [ADR 0010: Apex loetscher.io as the canonical host](decisions/0010-apex-as-canonical-host.md)
- [ADR 0011: CI checks without terraform plan or OIDC](decisions/0011-ci-checks-without-plan-or-oidc.md)
- [ADR 0012: Trivy in CI as a checksum-verified pinned binary](decisions/0012-trivy-pinned-binary.md)
- [Runbook](runbook.md)
