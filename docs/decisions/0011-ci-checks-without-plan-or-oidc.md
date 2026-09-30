# 0011: CI checks without terraform plan or OIDC

- **Status:** Accepted
- **Date:** 2026-09-30

## Context

The workflow `.github/workflows/terraform.yml` checks the Terraform code in `infra/`. Many projects also run `terraform plan` in CI (continuous integration: automatic checks on every change), so a pull request shows what would change in Azure.

A plan in CI needs two things:

1. **The state file.** Our state is local on the developer's Mac ([ADR 0006](0006-local-terraform-state.md)). Without it, a plan in CI would show every resource as "create", which is useless.
2. **An Azure login.** The usual secure way is **OIDC** (OpenID Connect): GitHub gives the workflow a short-lived identity token, and Azure trusts it through a "federated credential", so no password is stored in GitHub. But the budget lives at **subscription scope**, so even a read-only plan would need read access to the whole subscription. That conflicts with keeping CI access small.

## Decision

The Terraform workflow runs only static checks, with no Azure login:

- `terraform fmt -check -recursive`
- `terraform init -backend=false -lockfile=readonly` (downloads the pinned provider, checks it against the committed lock file, no state)
- `terraform validate`
- a Trivy misconfiguration scan ([ADR 0012](0012-trivy-pinned-binary.md))

It runs on **every** pull request (no path filter), because its job "fmt, validate, trivy" is the required status check in branch protection. A required check that is skipped by a path filter would block site-only pull requests forever. It also runs on pushes to `main` that touch `infra/` and can be started by hand.

`terraform plan` and `apply` stay local, with user approval.

## Consequences

Good:

- No Azure credentials in GitHub at all (apart from the Static Web App deployment token, which can only upload site content).
- Fast and free. Catches formatting errors, invalid code, and insecure settings before merge.

Bad, and how to handle it:

- Pull requests don't show a plan. Run `terraform plan` locally before merging any `infra/` change.
- Drift (Azure differing from the code) is not detected automatically. Run `terraform plan` locally from time to time; it should say `No changes`.

Later option (optional, not planned): add a remote backend together with an OIDC federated credential, then run `terraform plan` on pull requests. This would get its own ADR.
