# Runbook

Everyday tasks for loetscher.io, with copy-paste commands. Run the commands from the repository folder (your clone of `daloet/loetscher_io_azure`) unless a step says otherwise.

## Edit and preview the site locally

### Edit

All website files are in `site/`:

| File | What to edit there |
|------|--------------------|
| `site/index.html` | Page text and links |
| `site/404.html` | The "page not found" text |
| `site/css/style.css` | Colors, fonts, spacing (light and dark mode) |
| `site/favicon.svg` | The browser tab icon |

Rules (so the security headers keep working, see [security](security.md)):

- No inline `<script>`, no `onclick=` or other event handlers, no `style=` attributes. Put styles in `site/css/style.css`.
- Load nothing from other websites (no CDN fonts or scripts).
- External links get `rel="noopener noreferrer"`.

### Placeholders still to edit

In `site/index.html`:

1. The intro text (marked `EDIT ME`).
2. The LinkedIn URL: replace `REPLACE_ME` in `https://www.linkedin.com/in/REPLACE_ME`.
3. The email link: replace `REPLACE_ME@example.com` in the `mailto:` link.

Note: an email address in the page is public and can be collected by spammers.

### Preview

Start a small local web server (Python 3 comes with macOS):

```sh
python3 -m http.server -d site 8000
```

Open <http://localhost:8000> in your browser. Press `Ctrl+C` in the terminal to stop the server.

Good to know:

- To check dark mode, switch macOS to dark mode (System Settings > Appearance). The page follows it automatically.
- You can also double-click `site/index.html` to open it directly. The page then shows **without styles and icon**, because the page links to `/css/style.css` and `/favicon.svg`, which only resolve on a web server. Use the local server for a real preview.
- The local server does **not** apply `staticwebapp.config.json`. The security headers and the custom 404 page only work on Azure.

## Update the site

The repository is `daloet/loetscher_io_azure` on GitHub. The `main` branch is protected (see [security](security.md#branch-protection-on-main)), so **every change goes through a pull request (PR)**, even your own. You cannot push to `main` directly. A **pull request** is a request to merge a branch into `main`; GitHub runs the checks on it first.

1. Start from an up-to-date `main` and create a branch:
   ```sh
   git switch main
   git pull
   git switch -c my-change
   ```
2. Edit the files (for example in `site/`) and preview them locally (see [Preview](#preview)).
3. Commit. The pre-commit hook runs gitleaks and blocks the commit if it finds a secret:
   ```sh
   git add site/
   git commit -m "Update intro text"
   ```
4. Push the branch and open a pull request:
   ```sh
   git push -u origin my-change
   gh pr create --fill
   ```
5. Wait for the checks:
   ```sh
   gh pr checks --watch
   ```
   - **fmt, validate, trivy** always runs; it is required before merging.
   - **Build and deploy** runs if the PR changes `site/` or the deploy workflow. It creates a **preview environment** (a temporary copy of the site at its own public URL) and posts the URL as a comment on the PR.
6. Open the preview URL from the PR comment and check the change:
   ```sh
   gh pr view --comments
   ```
7. Merge. The history must stay linear, so use squash (or rebase), not a merge commit:
   ```sh
   gh pr merge --squash --delete-branch
   ```
   Merging closes the PR, which deletes its preview environment.
8. The push to `main` starts the production deployment. Watch it:
   ```sh
   gh run list -R daloet/loetscher_io_azure --workflow "Deploy site" --limit 3
   gh run watch -R daloet/loetscher_io_azure
   ```
9. Update your local `main`:
   ```sh
   git switch main
   git pull
   ```

Good to know:

- **Branch must be up to date.** If `main` changed after you opened the PR, GitHub asks you to update the branch first: `gh pr update-branch --rebase`, then wait for the checks again.
- **Open conversations block the merge.** Resolve all review comments on the PR first.
- **Preview URLs are public.** Don't put anything private in a PR.
- **Free tier: at most 3 preview environments.** Close PRs you no longer need.
- **Redeploy without a change:** `gh workflow run "Deploy site" -R daloet/loetscher_io_azure` deploys `main` to production again.

### Check the live site

Until DNS is done (Step 5), use the default hostname (`terraform output default_host_name` in `infra/`):

```sh
curl -I https://<swa-default-hostname>/
```

The response should include `content-security-policy`, `strict-transport-security`, `x-content-type-options`, `referrer-policy`, `permissions-policy`, `x-frame-options`, and `cross-origin-opener-policy`. Check the custom 404 page:

```sh
curl -s -o /dev/null -w "%{http_code}\n" https://<swa-default-hostname>/does-not-exist
```

It should print `404`.

## If a preview or deployment fails

1. Find the failed run and read only the failed steps:
   ```sh
   gh run list -R daloet/loetscher_io_azure --limit 5
   gh run view <run-id> -R daloet/loetscher_io_azure --log-failed
   ```
2. Match the error to a cause:

| Symptom | Cause | Fix |
|---------|-------|-----|
| No "Build and deploy" run at all on a PR | The PR doesn't touch `site/` or the deploy workflow, or it comes from a fork or Dependabot. These get no secrets, so the job is skipped on purpose. | Nothing to fix. Fork and Dependabot PRs get no preview. |
| Error about the maximum number of staging/preview environments | Free tier allows 3 previews at a time. | Close old PRs (`gh pr list`, `gh pr close <number>`). If an environment stays behind, list and delete it (commands below). |
| Error about an invalid or missing deployment token | The GitHub secret is missing, or the token was reset in Azure. | [Rotate the deployment token](#rotate-the-deployment-token). |
| Error parsing `staticwebapp.config.json` | Invalid JSON in the config file. | Fix the file, commit, and push to the same branch. |

List and delete leftover preview environments:

```sh
az staticwebapp environment list -n swa-loetscher-web -g rg-loetscher-web -o table
az staticwebapp environment delete -n swa-loetscher-web -g rg-loetscher-web --environment-name <environment-name>
```

Never delete the `default` environment: that is production.

3. After the fix, run the failed jobs again:
   ```sh
   gh run rerun <run-id> -R daloet/loetscher_io_azure --failed
   ```

## Handle Dependabot pull requests

**Dependabot** is a GitHub bot that opens PRs when a pinned dependency has a new version. It checks weekly for:

- GitHub Actions used in the workflows (it updates the SHA and the version comment), and
- the `azurerm` Terraform provider (it updates `.terraform.lock.hcl`).

It is set up **not** to propose two kinds of updates, which you do by hand (see the sections below):

- `Azure/static-web-apps-deploy`: Dependabot would "update" it to the old 2021 `v1` tag, which is a downgrade.
- **Major** versions of `azurerm` (for example 4.x to 5.x): these can contain breaking changes.

To handle a Dependabot PR:

1. List and inspect it:
   ```sh
   gh pr list -R daloet/loetscher_io_azure --author "app/dependabot"
   gh pr view <number> -R daloet/loetscher_io_azure
   gh pr diff <number> -R daloet/loetscher_io_azure
   ```
2. Read the release notes linked in the PR description. Look for breaking changes.
3. Check that the required check passed:
   ```sh
   gh pr checks <number> -R daloet/loetscher_io_azure
   ```
   Dependabot PRs get no preview (no secrets), so the deploy job doesn't run on them.
4. If `main` has moved on, ask Dependabot to rebase by commenting on the PR:
   ```sh
   gh pr comment <number> -R daloet/loetscher_io_azure --body "@dependabot rebase"
   ```
5. Merge or close:
   ```sh
   gh pr merge <number> -R daloet/loetscher_io_azure --squash --delete-branch
   # or, if you don't want it:
   gh pr close <number> -R daloet/loetscher_io_azure --comment "Not now: <reason>"
   ```
6. For an `azurerm` update, run `terraform init` and `terraform plan` locally after merging and `git pull`. The plan should say `No changes`.
7. If the update touched `deploy-site.yml`, the merge starts a production deployment. Check that it succeeds (`gh run list ...` as above).

### Update Azure/static-web-apps-deploy by hand

The workflow pins this action to the latest commit of its `v1` **branch**, because the `v1` tag is from 2021 and lacks inputs the workflow uses (`skip_api_build`, `production_branch`).

1. Look up the latest commit on the `v1` branch:
   ```sh
   gh api repos/Azure/static-web-apps-deploy/commits/v1 --jq '.sha + "  " + .commit.committer.date'
   ```
2. Check what changed since the pinned commit (the SHA in `.github/workflows/deploy-site.yml`):
   ```sh
   gh api repos/Azure/static-web-apps-deploy/compare/<old-sha>...<new-sha> --jq '.commits[].commit.message'
   ```
   Also open `https://github.com/Azure/static-web-apps-deploy/commit/<new-sha>` and confirm it is in the official `Azure` repository on the `v1` branch.
3. In a new branch, replace the SHA in **both** `uses:` lines of `deploy-site.yml` and update the date in the comment (`# v1 (branch head, YYYY-MM-DD)`).
4. Open a PR as in [Update the site](#update-the-site). The preview run tests the new version.

### Update Trivy in CI

Trivy in `.github/workflows/terraform.yml` is a pinned binary with a checksum ([ADR 0012](decisions/0012-trivy-pinned-binary.md)). Dependabot doesn't update it.

1. Pick the new version from <https://github.com/aquasecurity/trivy/releases> (for example `0.75.0`).
2. Get the SHA-256 for the Linux file from the release's checksums file:
   ```sh
   V=0.75.0
   curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${V}/trivy_${V}_checksums.txt" | grep "trivy_${V}_Linux-64bit.tar.gz"
   ```
3. Optional cross-check: download the file and verify its build-provenance attestation:
   ```sh
   curl -fsSLO "https://github.com/aquasecurity/trivy/releases/download/v${V}/trivy_${V}_Linux-64bit.tar.gz"
   shasum -a 256 "trivy_${V}_Linux-64bit.tar.gz"
   gh attestation verify "trivy_${V}_Linux-64bit.tar.gz" -R aquasecurity/trivy
   rm "trivy_${V}_Linux-64bit.tar.gz"
   ```
4. In a new branch, change `TRIVY_VERSION` and `TRIVY_SHA256` together in `terraform.yml`. Open a PR; the "fmt, validate, trivy" check tests the new binary.

### Upgrade azurerm to a new major version

Do this deliberately, not through Dependabot:

1. In a new branch, change the `azurerm` version constraint in `infra/versions.tf` (for example `~> 5.7.0`).
2. Read the provider's upgrade guide for that major version.
3. Update the provider and the lock file for both platforms (Mac and GitHub runners):
   ```sh
   cd infra
   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   terraform init -upgrade
   terraform providers lock -platform=darwin_arm64 -platform=linux_amd64
   terraform fmt -check -recursive && terraform validate && trivy config .
   terraform plan
   ```
4. Review the plan carefully. Ideally it says `No changes`. Anything that would destroy or replace a resource needs a closer look before you go on.
5. Commit `versions.tf` and `.terraform.lock.hcl` and open a PR.

## Rotate the deployment token

The **deployment token** is the secret that lets GitHub Actions upload the site. It is stored in the GitHub secret `AZURE_STATIC_WEB_APPS_API_TOKEN` and in the local `infra/terraform.tfstate`. Rotating means replacing it with a new one, for example if it may have leaked. Never print it or paste it into files or chats.

Setting a secret and changing state need your explicit approval when an agent does it.

1. Create a new token in Azure. The old one stops working immediately, so deployments fail until step 3 is done:
   ```sh
   az staticwebapp secrets reset-api-key -n swa-loetscher-web -g rg-loetscher-web -o none
   ```
   (`-o none` keeps the new token off the screen.)
2. Let Terraform read the new token into its state, without changing any resources:
   ```sh
   cd infra
   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   terraform apply -refresh-only
   ```
   Read the output, then type `yes`. This updates the state file only.
3. Pipe the new token straight into the GitHub secret, without printing it:
   ```sh
   terraform output -raw deployment_token | gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN -R daloet/loetscher_io_azure
   ```
4. Check that a deployment works with the new token:
   ```sh
   gh workflow run "Deploy site" -R daloet/loetscher_io_azure
   gh run watch -R daloet/loetscher_io_azure
   ```
5. Update your private backup of `infra/terraform.tfstate`.

## Renew the GitHub CLI token

`gh` is logged in with a **fine-grained personal access token (PAT)**, which has an expiry date. When it expires, `gh` and `git push` fail with an authentication error. Create a new token with the same permissions and log in again as in [setup, section 6](setup.md#6-log-in-to-github-and-get-the-code). Check with:

```sh
gh auth status
```

## Check the budget

The subscription budget `budget-monthly-subscription` is 5 CHF per month, running from 2026-09-01 to 2036-09-01. It emails `<budget-alert-email>` at 20% actual cost (1 CHF), 100% actual cost, and 100% forecast cost. It only alerts; it does **not** stop spending. See [ADR 0005](decisions/0005-subscription-level-budget.md).

### In the Azure portal

1. Open <https://portal.azure.com> and search for **Cost Management**.
2. Select **Budgets**.
3. Make sure the **scope** (shown at the top) is your subscription. If not, select **Scope** and pick the subscription.
4. Open **budget-monthly-subscription**. It shows the amount, the current spend, and the alert conditions.

### With the Azure CLI

```sh
az consumption budget show --budget-name budget-monthly-subscription
```

The full output includes the alert email and the subscription ID. To see only the key numbers:

```sh
az consumption budget show --budget-name budget-monthly-subscription \
  --query "{name:name, amount:amount, spent:currentSpend.amount, unit:currentSpend.unit, start:timePeriod.startDate}" \
  -o table
```

At the time of Step 2 the current spend was 0.

### With Terraform

Check that Azure still matches the code:

```sh
cd infra
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform plan
```

It should say `No changes`. The budget's start date never shows as a change, because `budget.tf` ignores `time_period` after creation.

### Free tier: why there should be no costs

The Static Web App is on the Free plan: 100 GB bandwidth per month, 2 custom domains, 3 preview environments. Free has no overage billing, so it cannot incur charges. If the budget ever reports spend, something else in the subscription is costing money. Look under **Cost Management** > **Cost analysis**, grouped by resource.

### Change the amount

1. Set `budget_amount` in `infra/terraform.tfvars` (for example `budget_amount = 10`).
2. Run `terraform plan -out=tfplan`, check it, then `terraform apply tfplan` and `rm tfplan`.

## Troubleshoot Terraform

### Terraform apply fails with 403 AuthorizationFailed

**Symptom:** `terraform apply` fails with an error like `AuthorizationFailed ... does not have authorization to perform action 'Microsoft.Consumption/budgets/write'`.

**Cause:** The logged-in account has no suitable role **on the subscription**. In Step 2 this happened because the account only had **User Access Administrator** at root scope `/`. That role manages access, but it does not allow creating resources such as budgets.

**Fix:**

1. List your role assignments:
   ```sh
   az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" --all -o table
   ```
   Look for a row whose `Scope` starts with `/subscriptions/`.
2. If there is none, give the account **Owner** or **Contributor** on the subscription: in the portal, open **Subscriptions** > your subscription > **Access control (IAM)** > **Add** > **Add role assignment**. (In Step 2 the account was given Owner.)
3. Wait a few minutes for the role to take effect, then log in again and retry:
   ```sh
   az login
   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   terraform plan -out=tfplan
   ```
4. Afterwards, remove the root-scope User Access Administrator: **Microsoft Entra ID** > **Properties** > **Access management for Azure resources** > **No** > **Save**. (Done for this project on 2026-09-29.) See [security](security.md#least-privilege-for-the-azure-account).

### Static Web App rejected: region not accepting new customers

**Symptom:** `terraform apply` creates the resource group, but the Static Web App fails with:

```
RequestDisallowedByAzure: The selected region is currently not accepting new customers
```

and a link to <https://aka.ms/locationineligible>.

**Cause:** Azure does not accept new Static Web Apps in that region for your subscription right now. In Step 3 this happened with `westeurope`.

**Fix:**

1. Choose another region that supports Static Web Apps: `westeurope`, `centralus`, `eastus2`, `westus2`, or `eastasia`. The project default is `eastus2`. The region only holds metadata; visitors are served from Azure's global edge, so speed is not affected.
2. If you need a different region than the default, set it in `infra/terraform.tfvars`:
   ```hcl
   static_web_app_location = "centralus"
   ```
   Leave `location` (the resource group region) as it is.
3. Plan and apply again:
   ```sh
   terraform plan -out=tfplan
   terraform apply tfplan
   rm tfplan
   ```

See [ADR 0008](decisions/0008-swa-region-eastus2.md). Warning: changing the region of an **existing** Static Web App replaces it, which creates a new default hostname and a new deployment token.

### Microsoft.Web registration fails during plan

The provider registers `Microsoft.Web` when it starts, so even `terraform plan` needs permission to register resource providers on the subscription (Owner or Contributor). If `plan` fails with an authorization error about resource provider registration, check your role as in [403 AuthorizationFailed](#terraform-apply-fails-with-403-authorizationfailed). To see the registration state:

```sh
az provider show --namespace Microsoft.Web --query registrationState -o tsv
```

It should print `Registered`.

### Error about a missing `subscription_id`

If `terraform plan` or `apply` complains that `subscription_id` is required, Terraform does not know which subscription to use. Set the environment variable in the current Terminal window and try again:

```sh
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
```

## DNS records at Hostpoint

DNS records are edited by hand in the Hostpoint control panel (see [ADR 0003](decisions/0003-dns-at-hostpoint-manual-records.md)). The canonical host is the apex `loetscher.io` ([ADR 0010](decisions/0010-apex-as-canonical-host.md)).

### Get the values

```sh
cd infra
export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
terraform output dns_records
```

It lists three records. In these docs the real values are replaced by placeholders:

| # | Type | Host | Value |
|---|------|------|-------|
| 1 | `TXT` | `@` | `<txt-validation-token>` |
| 2 | `ANAME` | `@` | `<swa-default-hostname>` (like `<random-name>.azurestaticapps.net`) |
| 3 | `CNAME` | `www` | `<swa-default-hostname>` |

`@` means the apex, `loetscher.io` itself. An **ANAME** record points the apex at a hostname; Hostpoint looks up that hostname's addresses and answers with them. (A plain `CNAME` is not allowed at the apex.)

### Change the records

1. Log in to the Hostpoint control panel and open the DNS zone of `loetscher.io`.
2. **Delete** any existing `A` or `AAAA` record for `@` (for example Hostpoint's parking page).
3. **Delete** any existing record for `www` (also often parking).
4. **Keep** the `MX` records and all other mail-related records (for example SPF `TXT`, autoconfig). Deleting them breaks email.
5. **Add** the three records from the table above.
6. Save. Changes can take from a few minutes up to a few hours to be visible, depending on the old records' **TTL** (time to live: how long resolvers may cache a record).

### Check the records

```sh
dig +short TXT loetscher.io
```
Should include `"<txt-validation-token>"` (and any mail `TXT` records, such as SPF).

```sh
dig +short loetscher.io
```
Should print one or more IP addresses. With an `ANAME`, you see the addresses of `<swa-default-hostname>`, not the name itself. Compare with `dig +short <swa-default-hostname>`.

```sh
dig +short CNAME www.loetscher.io
```
Should print `<swa-default-hostname>.` (with a trailing dot).

### Check the domain status in Azure

```sh
az staticwebapp hostname list -n swa-loetscher-web -g rg-loetscher-web -o table
```

This lists the custom domains and their status. `loetscher.io` becomes `Ready` once Azure has found the `TXT` record. Azure then issues the free TLS certificate automatically.

### Add the www domain

Only once `dig +short CNAME www.loetscher.io` shows the right value: set `enable_www_domain = true` in `infra/terraform.tfvars`, then plan and apply. See [setup, second apply](setup.md#second-apply-www-domain) and [ADR 0009](decisions/0009-two-step-custom-domain-rollout.md).

### Redirect www to the apex (planned, Step 5)

In the Azure portal, open the Static Web App **swa-loetscher-web** > **Custom domains** and set `loetscher.io` as the **default domain**. Other domains then redirect to it. This setting exists only in the portal; Terraform and the Azure CLI cannot set it. The exact steps will be confirmed in Step 5.

## Troubleshoot DNS and SSL

More checks for SSL/TLS certificates will be added in Step 5.

### Apex domain stays in "Validating"

1. Check the `TXT` record: `dig +short TXT loetscher.io`. The token must match `terraform output dns_records` exactly, with no extra spaces or quotes typed into the Hostpoint field.
2. Check that the `TXT` record is at `@`, not at `www` or a subdomain.
3. Wait. Azure checks in the background, which can take a while after the record appears.
4. If the TXT row in `terraform output dns_records` shows "already validated", Azure has validated the domain. Leave the `TXT` record in place.

### Apply fails when adding the www domain

**Cause:** `cname-delegation` validation runs immediately. The `CNAME www` record is missing, wrong, or not visible yet.

**Fix:** check `dig +short CNAME www.loetscher.io`. If it is empty or wrong, set `enable_www_domain = false` again (or fix the record and wait), then retry the plan and apply once `dig` shows `<swa-default-hostname>.`.

### Apex shows the old site or Hostpoint's parking page

An old `A` or `AAAA` record for `@` still exists, or the old answer is cached. Delete the old record at Hostpoint and wait for the TTL to run out. `dig +short loetscher.io` should only show the Static Web App's addresses.
