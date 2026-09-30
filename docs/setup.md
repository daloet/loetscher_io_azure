# Setup from scratch

These steps set up a new Mac (Apple Silicon, zsh) to work on loetscher.io. Run them in order in the Terminal app.

Versions used on 2026-09-29 are listed so you can compare. Newer versions will usually work too.

| Tool | Version | Purpose |
|------|---------|---------|
| git | 2.50.1 | Version control |
| terraform | 1.16.4 | Creates Azure resources from code |
| gh (GitHub CLI) | 2.101.0 | Works with GitHub from the terminal |
| az (Azure CLI) | 2.90.0 | Works with Azure from the terminal |
| gitleaks | 8.30.1 | Finds secrets before they are committed |
| trivy | 0.74.0 | Scans Terraform code for security problems |

The Terraform code pins Terraform to `~> 1.16.0` (any 1.16.x) and the `azurerm` provider to `~> 4.81.0` (any 4.81.x). A different Terraform minor version (for example 1.17) will refuse to run.

## 1. Install Homebrew

**Homebrew** is a package manager for macOS: it installs command-line tools for you. Skip this if `brew --version` already works.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

At the end, the installer prints two or three commands that add `brew` to your shell. Run them, then open a new Terminal window.

## 2. Install git and the GitHub CLI

macOS may already include git. Installing it with Homebrew is also fine.

```sh
brew install git gh
```

## 3. Install Terraform

Terraform comes from HashiCorp's own Homebrew **tap** (an extra package source).

```sh
brew tap hashicorp/tap
brew install hashicorp/tap/terraform
```

## 4. Install the Azure CLI, gitleaks, and trivy

```sh
brew install azure-cli gitleaks trivy
```

## 5. Check the versions

```sh
git --version
terraform version
gh --version
az version
gitleaks version
trivy --version
```

Each command should print a version number.

## 6. Log in to GitHub

```sh
gh auth login
```

Follow the prompts: choose **GitHub.com**, **HTTPS**, and **Login with a web browser**. Check the result:

```sh
gh auth status
```

## 7. Log in to Azure

```sh
az login
```

A browser window opens. Sign in with your Azure account. If you have several subscriptions, the CLI asks you to pick one.

Confirm which subscription is active:

```sh
az account show --query "{name:name, state:state}" --output table
```

This prints only the name and state, so no IDs appear on screen. If it shows the wrong subscription, switch:

```sh
az account list --query "[].name" --output table
az account set --subscription "<your-subscription-name-or-id>"
```

## 8. Terraform first run

This creates the subscription budget (Step 2), on its own, before anything else. All commands run in the `infra/` folder. Section 9 then adds the Static Web App.

### Before you start: check your Azure role

Your account needs a role **on the subscription** that may create budgets, such as **Owner** or **Contributor** (**Cost Management Contributor** is enough for the budget alone). A role only at root scope `/` (for example "User Access Administrator") is **not** enough. List your roles:

```sh
az role assignment list --assignee "$(az ad signed-in-user show --query id -o tsv)" --all -o table
```

Look for a row whose `Scope` starts with `/subscriptions/`. If there is none, see [403 AuthorizationFailed](runbook.md#terraform-apply-fails-with-403-authorizationfailed) in the runbook.

### Steps

1. Go to the Terraform folder:
   ```sh
   cd infra
   ```
2. Create your own variables file from the template. `terraform.tfvars` is gitignored, so your real values stay on your Mac:
   ```sh
   cp terraform.tfvars.example terraform.tfvars
   ```
3. Open `terraform.tfvars` in an editor and replace the example address with `<budget-alert-email>` (the inbox that should get budget alerts). You can also set `budget_amount` (default `5`, in your billing currency).
4. Tell Terraform which subscription to use. The ID is read from an **environment variable** (a value that lives only in this Terminal session), so it is never written to a file. See [ADR 0007](decisions/0007-subscription-id-via-env-var.md):
   ```sh
   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   ```
   Run this again in every new Terminal window before using Terraform.
5. Download the pinned provider. The committed `.terraform.lock.hcl` makes sure you get exactly the tested version:
   ```sh
   terraform init
   ```
6. Check the code:
   ```sh
   terraform fmt -check
   terraform validate
   trivy config .
   ```
   `trivy` should report 0 misconfigurations.
7. Create a **plan** (a preview of what Terraform will change) for the budget only, and save it to a file. `-target` limits the plan to one resource; use it only for this bootstrap, not for everyday runs:
   ```sh
   terraform plan -target=azurerm_consumption_budget_subscription.monthly -out=tfplan
   ```
   Read it. It should create one resource, `azurerm_consumption_budget_subscription.monthly` (defined in `budget.tf`). The start date shows as "known after apply" because it is computed at apply time (the first day of the current month). Terraform also warns that `-target` is in use; that is expected here.

   Note: the provider registers the `Microsoft.Web` resource provider when it starts, so this already happens during `plan` (see section 9).
8. Apply exactly that saved plan:
   ```sh
   terraform apply tfplan
   ```
9. Delete the plan file. It contains your variables in plain text, including the alert email:
   ```sh
   rm tfplan
   ```
10. Check the result: see [Check the budget](runbook.md#check-the-budget).

After the apply, `infra/terraform.tfstate` exists on your Mac. It is gitignored. Keep a private backup of it (see [security](security.md#local-terraform-state)).

## 9. Static Web App and custom domains

This creates the resource group, the Static Web App, and the custom domains (Step 3). All commands run in the `infra/` folder, with `ARM_SUBSCRIPTION_ID` set as in section 8.

Good to know before you start:

- **Resource provider.** Azure services must be "registered" on a subscription before you can use them. `infra/versions.tf` registers only `Microsoft.Web` (the namespace for Static Web Apps), through the provider setting `resource_providers_to_register`. This happens when the provider starts, so already during `terraform plan`, not only on apply. Registration is free. Your account needs a subscription role such as Owner or Contributor for this.
- **Two regions.** The resource group is in `westeurope` (variable `location`). The Static Web App is in `eastus2` (variable `static_web_app_location`), because `westeurope` did not accept new Static Web Apps. See [ADR 0008](decisions/0008-swa-region-eastus2.md).
- **Two applies.** The `www` domain can only be added after its DNS record exists, so it is off by default (`enable_www_domain = false`). See [ADR 0009](decisions/0009-two-step-custom-domain-rollout.md).

### First apply: Static Web App and apex domain

1. Check the code:
   ```sh
   terraform fmt -check
   terraform validate
   trivy config .
   ```
2. Create and save a plan (no `-target` this time):
   ```sh
   terraform plan -out=tfplan
   ```
   Read it. It should create `azurerm_resource_group.web`, `azurerm_static_web_app.web`, and `azurerm_static_web_app_custom_domain.apex`, and change nothing on the budget.
3. Apply exactly that plan, then delete the plan file:
   ```sh
   terraform apply tfplan
   rm tfplan
   ```
   If Azure rejects the Static Web App with "region is currently not accepting new customers", see the [runbook](runbook.md#static-web-app-rejected-region-not-accepting-new-customers).
4. Show the Static Web App's default hostname and the DNS records to create:
   ```sh
   terraform output default_host_name
   terraform output dns_records
   ```
   The hostname looks like `<random-name>.azurestaticapps.net` (`<swa-default-hostname>` in these docs). The TXT value is `<txt-validation-token>`. Neither is a secret, but these docs don't copy the real values.

   **Never** run `terraform output deployment_token` without `| gh secret set ...`. The token is a secret; it will be piped straight into GitHub in Step 4.

### DNS records at Hostpoint

5. Create the records at Hostpoint as described in the runbook: [DNS records at Hostpoint](runbook.md#dns-records-at-hostpoint). Then check them with `dig` (same section).

### Second apply: www domain

6. Only after `dig +short CNAME www.loetscher.io` returns `<swa-default-hostname>.`, open `infra/terraform.tfvars` and add:
   ```hcl
   enable_www_domain = true
   ```
7. Plan and apply again:
   ```sh
   terraform plan -out=tfplan
   terraform apply tfplan
   rm tfplan
   ```
   The plan should add only `azurerm_static_web_app_custom_domain.www[0]`.
8. Check the domain status:
   ```sh
   az staticwebapp hostname list -n swa-loetscher-web -g rg-loetscher-web -o table
   ```
9. Update your private backup of `infra/terraform.tfstate`. It now also contains the deployment token (see [security](security.md#local-terraform-state)).

Planned (Step 5): make `loetscher.io` the default domain in the Azure portal, so `www` redirects to it. See [ADR 0010](decisions/0010-apex-as-canonical-host.md).

## Next steps

- Edit and preview the website: [runbook](runbook.md#edit-and-preview-the-site-locally).
- Planned: steps for the GitHub repo and CI/CD (Step 4) and DNS verification (Step 5) will be added here as they are completed.
