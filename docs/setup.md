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

## 6. Log in to GitHub and get the code

The code lives in the public GitHub repository **`daloet/loetscher_io_azure`**. (It was created on github.com with an "Initial commit"; the project history sits on top of it.)

### Create a fine-grained access token

`gh` (and, through it, `git push`) logs in with a **fine-grained personal access token (PAT)**: a password-like key that only works for the repositories and permissions you choose.

1. On github.com, open **Settings** > **Developer settings** > **Personal access tokens** > **Fine-grained tokens** > **Generate new token**.
2. Give it a name (for example `loetscher-io-cli`) and an **expiration date**.
3. Under **Repository access**, choose **Only select repositories** and pick `daloet/loetscher_io_azure`.
4. Under **Repository permissions**, set to **Read and write**:
   - **Contents** (push code)
   - **Workflows** (change files in `.github/workflows/`)
   - **Secrets** (set `AZURE_STATIC_WEB_APPS_API_TOKEN`)
   - **Administration** (repository settings such as branch protection)

   **Metadata: Read** is added automatically.
5. Select **Generate token** and copy it. GitHub shows it only once.

Never paste the token into a chat, a file, an issue, or a commit.

### Log in with the token

```sh
gh auth login --with-token
```

The command waits for input. Paste the token, press `Enter`, then press `Ctrl+D`. The token goes straight into `gh`'s secure storage (the macOS keychain). Then let Git use `gh` for HTTPS logins, so `git push` needs no separate password:

```sh
gh auth setup-git
gh auth status
```

**Token expiry:** when the PAT expires, `gh` and `git push` stop working. Create a new token with the same repository and permissions, and run `gh auth login --with-token` again. See [Renew the GitHub CLI token](runbook.md#renew-the-github-cli-token).

### Clone the repository

```sh
git clone https://github.com/daloet/loetscher_io_azure.git
cd loetscher_io_azure
```

The remote uses HTTPS (not SSH); the credential helper from `gh auth setup-git` handles the login.

### Set your Git identity for this repository

Every commit records a name and an email, and in a public repository everyone can read them. Use GitHub's **noreply address** so your real email stays private. Find it on github.com under **Settings** > **Emails** ("Keep my email addresses private"). Set it for this repository only (no `--global`):

```sh
git config user.name "<your-name>"
git config user.email "<id>+<user>@users.noreply.github.com"
```

### Turn on the pre-commit hook

The repository contains a **pre-commit hook** (a script Git runs before each commit) in `.githooks/pre-commit`. It runs `gitleaks git --pre-commit --staged` and blocks the commit if it finds a secret. Git does not use it automatically. **Every fresh clone needs this command once:**

```sh
git config core.hooksPath .githooks
```

Check it: `git config core.hooksPath` should print `.githooks`. If gitleaks is not installed, the hook blocks every commit and tells you to install it (step 4).

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

This creates the subscription budget (Step 2), on its own, before anything else. All commands run in the `infra/` folder of your clone. Section 9 then adds the Static Web App.

Note: `main` is protected, so code changes (even to `infra/`) go through a pull request; see [Update the site](runbook.md#update-the-site). The Terraform commands themselves always run locally.

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

   **Never** run `terraform output deployment_token` without `| gh secret set ...`. The token is a secret; it is piped straight into GitHub in [section 10](#10-github-repository-and-cicd).

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

## 10. GitHub repository and CI/CD

This connects the repository to the Static Web App and locks down `main` (Step 4). You need the logins from section 6 and the Terraform state from section 9. The workflows themselves are already in the repository:

- `.github/workflows/deploy-site.yml` ("Deploy site"): deploys `site/` to production on pushes to `main`, and to preview environments for pull requests.
- `.github/workflows/terraform.yml` ("Terraform checks"): runs `fmt`, `validate`, and Trivy on every pull request.
- `.github/dependabot.yml`: weekly update PRs for actions and the `azurerm` provider.

See [architecture](architecture.md) for how they fit together.

1. Store the deployment token as a GitHub secret. It is piped straight from Terraform into GitHub and never shown:
   ```sh
   cd infra
   export ARM_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
   terraform output -raw deployment_token | gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN -R daloet/loetscher_io_azure
   gh secret list -R daloet/loetscher_io_azure
   ```
   `gh secret list` shows only the name and date, never the value.
2. Push `main` (only possible before branch protection is on; afterwards everything goes through pull requests). The push starts the first production deployment:
   ```sh
   git push -u origin main
   gh run watch -R daloet/loetscher_io_azure
   ```
3. Turn on GitHub's security features: **secret scanning**, **push protection**, **Dependabot alerts**, and **Dependabot security updates**. In the browser: repository **Settings** > **Code security**. Or with `gh`:
   ```sh
   gh api -X PATCH repos/daloet/loetscher_io_azure \
     -f "security_and_analysis[secret_scanning][status]=enabled" \
     -f "security_and_analysis[secret_scanning_push_protection][status]=enabled"
   gh api -X PUT repos/daloet/loetscher_io_azure/vulnerability-alerts
   gh api -X PUT repos/daloet/loetscher_io_azure/automated-security-fixes
   ```
4. Protect `main`. The required check `fmt, validate, trivy` must have run at least once (open a pull request, or run the "Terraform checks" workflow by hand) so GitHub knows its name. In the browser: **Settings** > **Branches**. Or with `gh`:
   ```sh
   gh api -X PUT repos/daloet/loetscher_io_azure/branches/main/protection --input - <<'EOF'
   {
     "required_status_checks": { "strict": true, "checks": [ { "context": "fmt, validate, trivy", "app_id": 15368 } ] },
     "enforce_admins": true,
     "required_pull_request_reviews": { "required_approving_review_count": 0, "dismiss_stale_reviews": true },
     "restrictions": null,
     "required_linear_history": true,
     "required_conversation_resolution": true,
     "allow_force_pushes": false,
     "allow_deletions": false
   }
   EOF
   ```
   What each setting means is explained in [security](security.md#branch-protection-on-main).
5. Check the deployed site on its default hostname, as in [Check the live site](runbook.md#check-the-live-site).

From now on, every change goes through a pull request: see [Update the site](runbook.md#update-the-site).

## Next steps

- Edit and preview the website: [runbook](runbook.md#edit-and-preview-the-site-locally).
- Planned: DNS verification and the `www` redirect (Step 5) will be added here once completed.
