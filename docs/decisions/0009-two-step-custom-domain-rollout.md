# 0009: Two-step custom domain rollout

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

The site gets two **custom domains** (your own domain names instead of the generated `<random-name>.azurestaticapps.net`): `loetscher.io` and `www.loetscher.io`. Azure must first check that we own each domain. This check is called **validation**. The two domains use different validation types:

- **Apex `loetscher.io`: `dns-txt-token`.** Azure generates a random token. We publish it as a `TXT` record in DNS. Terraform creates the domain, stores the token, and finishes **without waiting**. Azure keeps checking DNS in the background until the record appears.
- **`www.loetscher.io`: `cname-delegation`.** Azure checks **immediately** that a `CNAME` record for `www` points to the Static Web App. Terraform waits for the result. If the record doesn't exist yet, the apply **fails**.

DNS is at Hostpoint and edited by hand ([ADR 0003](0003-dns-at-hostpoint-manual-records.md)), so Terraform cannot create the records itself. And the `CNAME` needs the Static Web App's default hostname, which only exists after the first apply.

## Decision

Roll out the domains in two steps, controlled by the Terraform variable `enable_www_domain` (default `false`):

1. Apply with `enable_www_domain = false`. This creates the resource group, the Static Web App, and the apex domain (which returns the `TXT` token).
2. Create the DNS records at Hostpoint by hand. `terraform output dns_records` lists them.
3. Set `enable_www_domain = true` in `infra/terraform.tfvars` and apply again. This adds the `www` domain.

## Consequences

- No apply fails because a DNS record is missing.
- Step 3 of the rollout is manual and easy to forget. The runbook lists it: [DNS records at Hostpoint](../runbook.md#dns-records-at-hostpoint).
- `terraform output dns_records` is the single source for the record values. The docs only use placeholders (`<swa-default-hostname>`, `<txt-validation-token>`).
- Once the apex is validated, Azure no longer returns the TXT token. The output then shows a note instead. The existing `TXT` record should stay in place.
