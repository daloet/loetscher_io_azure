# Runbook

Everyday tasks for loetscher.io, with copy-paste commands. Run the commands from the repository folder unless a step says otherwise.

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

## Deploy a change (planned, Step 4)

Once the GitHub repo and workflow exist, commit and push to `main`. GitHub Actions then deploys `site/` automatically. The exact commands will be added in Step 4. For now, see [How to deploy changes](../README.md#how-to-deploy-changes-planned).

## Rotate the deployment token (planned, Step 4)

The **deployment token** is the secret that lets GitHub Actions upload the site. Rotating means replacing it with a new one, for example if it may have leaked. The token exists since Step 3 (Terraform output `deployment_token`). It will be stored as the GitHub secret `AZURE_STATIC_WEB_APPS_API_TOKEN` in Step 4 and must never be printed or pasted into files.

Planned procedure (usable once the GitHub secret exists in Step 4; setting a secret needs user approval):

1. Create a new token in Azure. The old one stops working immediately, so deployments fail until step 3 is done:
   ```sh
   az staticwebapp secrets reset-api-key -n swa-loetscher-web -g rg-loetscher-web
   ```
2. Let Terraform read the new token into its state, without changing any resources:
   ```sh
   cd infra
   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   terraform apply -refresh-only
   ```
   Read the output, then type `yes`.
3. Pipe the new token straight into the GitHub secret, without printing it:
   ```sh
   terraform output -raw deployment_token | gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN
   ```
4. Update your private backup of `infra/terraform.tfstate`.

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
