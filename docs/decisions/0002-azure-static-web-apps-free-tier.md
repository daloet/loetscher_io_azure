# 0002: Host on Azure Static Web Apps, Free tier

- **Status:** Accepted
- **Date:** 2026-09-29
- **Note:** the Static Web App's region was changed to `eastus2` by [0008](0008-swa-region-eastus2.md); the resource group stays in `westeurope`.

## Context

The site should cost $0 per month, serve over HTTPS on a custom domain, and deploy from GitHub. It should also be a learning project for Azure and Terraform.

## Decision

Host the site on **Azure Static Web Apps** with the **Free** plan (`sku_tier` and `sku_size` = `Free`), in resource group `rg-loetscher-web`, region `westeurope`. Create it with Terraform (Step 3) and deploy with GitHub Actions (Step 4).

A subscription budget of 5 per month, with email alerts, is created first as a safety net (Step 2).

## Consequences

- No hosting cost. The Free plan includes managed TLS certificates for custom domains.
- Security headers and the custom 404 page are configured in `site/staticwebapp.config.json`.
- The Free plan has limits and no uptime guarantee (SLA). As of 2026-09-29: 100 GB bandwidth per month, 2 custom domains, and 3 preview environments. The Free plan has no overage billing, so traffic above the quota cannot be charged. These limits are fine for a personal site. Check the current limits in the Azure documentation.
- The Standard plan costs money and must not be used. Any change that could cost money is flagged before it is made.
