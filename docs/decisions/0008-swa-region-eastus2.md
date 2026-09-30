# 0008: Static Web App region eastus2

- **Status:** Accepted (amends the region in [0002](0002-azure-static-web-apps-free-tier.md))
- **Date:** 2026-09-29

## Context

The plan was to put everything in `westeurope` ([ADR 0002](0002-azure-static-web-apps-free-tier.md)). The first Step 3 apply created the resource group `rg-loetscher-web` in `westeurope`. Azure then rejected the Static Web App with:

```
RequestDisallowedByAzure: The selected region is currently not accepting new customers
```

(see <https://aka.ms/locationineligible>). This is a capacity restriction set by Azure for this subscription and region. It is not a setting we can change.

For a Static Web App, the **region** only decides where Azure stores the app's metadata (its settings and configuration). The website files themselves are served from Azure's global **edge** network (servers close to visitors all over the world), no matter which region is chosen. Only a few regions support Static Web Apps: `westeurope`, `centralus`, `eastus2`, `westus2`, and `eastasia`.

## Decision

- Add a Terraform variable `static_web_app_location` (default `eastus2`) in `infra/variables.tf`. A validation rule allows only the five regions listed above.
- The Static Web App `swa-loetscher-web` is created in `eastus2`.
- The resource group stays in `westeurope` (variable `location`). A resource group and the resources inside it may be in different regions.

## Consequences

- The Static Web App could be created. Visitors in Europe are not slower, because content comes from the global edge.
- The app's metadata is stored in the US. The site is public and has no backend or user data, so this does not matter here.
- Two region variables now exist: `location` (resource group) and `static_web_app_location` (Static Web App). Don't mix them up.
- Changing `static_web_app_location` later would make Terraform **replace** (delete and re-create) the Static Web App. That creates a new default hostname and a new deployment token, so DNS records and the GitHub secret would need updating.
- Troubleshooting: see [the runbook](../runbook.md#static-web-app-rejected-region-not-accepting-new-customers).
