# 0010: Apex loetscher.io as the canonical host

- **Status:** Accepted (answers the open question in [0003](0003-dns-at-hostpoint-manual-records.md))
- **Date:** 2026-09-29

## Context

The **canonical host** is the one address a site officially uses. Other addresses redirect to it, so search engines and visitors see one consistent URL. The choice was between the **apex** `loetscher.io` (the bare domain) and `www.loetscher.io`.

The DNS standard does not allow a `CNAME` record at the apex. Pointing the apex at a Static Web App therefore needs a special record type, `ALIAS` or `ANAME`, which the DNS provider resolves to an address for you. Hostpoint supports `ANAME`.

## Decision

- The canonical host is the apex **`loetscher.io`**.
- DNS at Hostpoint: `ANAME @` points to the Static Web App's default hostname; `CNAME www` points to the same hostname.
- `www.loetscher.io` redirects to `loetscher.io`. **Planned (Step 5):** this is done with the Static Web App's "default domain" setting. That setting exists only in the Azure portal; Terraform and the Azure CLI cannot set it.

## Consequences

- The site uses the short address `loetscher.io`.
- The apex relies on Hostpoint's `ANAME` support. If the site ever moves to a DNS provider without `ALIAS`/`ANAME`, this decision must be revisited.
- One setting (the default domain) lives outside Terraform. It is documented in the runbook and must be checked by hand after re-creating the Static Web App.
- The Free tier allows 2 custom domains, so apex plus `www` uses the full quota.
