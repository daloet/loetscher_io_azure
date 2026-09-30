# Architecture decision records

An **architecture decision record (ADR)** is a short note that explains one important choice: the situation, what was decided, and what follows from it. New ADRs get the next number. Old ADRs are not deleted; if a decision changes, a new ADR replaces it and the old one is marked "Superseded".

| # | Title | Status | Date |
|---|-------|--------|------|
| [0001](0001-plain-html-no-build.md) | Plain HTML and CSS, no build step | Accepted | 2026-09-29 |
| [0002](0002-azure-static-web-apps-free-tier.md) | Host on Azure Static Web Apps, Free tier | Accepted | 2026-09-29 |
| [0003](0003-dns-at-hostpoint-manual-records.md) | Keep DNS at Hostpoint with manual records | Accepted | 2026-09-29 |
| [0004](0004-strict-csp-no-inline-code.md) | Strict CSP and no inline code | Accepted | 2026-09-29 |
| [0005](0005-subscription-level-budget.md) | Subscription-level budget with an early warning | Accepted | 2026-09-29 |
| [0006](0006-local-terraform-state.md) | Local Terraform state | Accepted | 2026-09-29 |
| [0007](0007-subscription-id-via-env-var.md) | Subscription ID via environment variable | Accepted | 2026-09-29 |
| [0008](0008-swa-region-eastus2.md) | Static Web App region eastus2 | Accepted | 2026-09-29 |
| [0009](0009-two-step-custom-domain-rollout.md) | Two-step custom domain rollout | Accepted | 2026-09-29 |
| [0010](0010-apex-as-canonical-host.md) | Apex loetscher.io as the canonical host | Accepted | 2026-09-29 |
| [0011](0011-ci-checks-without-plan-or-oidc.md) | CI checks without terraform plan or OIDC | Accepted | 2026-09-30 |
| [0012](0012-trivy-pinned-binary.md) | Trivy in CI as a checksum-verified pinned binary | Accepted | 2026-09-30 |

## Template

```markdown
# NNNN: Title

- **Status:** Proposed | Accepted | Superseded by NNNN
- **Date:** YYYY-MM-DD

## Context
## Decision
## Consequences
```
