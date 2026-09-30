# 0003: Keep DNS at Hostpoint with manual records

- **Status:** Accepted
- **Date:** 2026-09-29

## Context

The domain `loetscher.io` uses **Hostpoint** as its DNS provider. DNS could be moved to an Azure DNS zone and managed by Terraform, but an Azure DNS zone costs money every month. The project goal is $0 per month. Only a few records are needed, and they rarely change.

## Decision

Keep DNS at Hostpoint. The user adds and changes the DNS records by hand in the Hostpoint control panel. Terraform does not manage DNS.

## Consequences

- No DNS cost in Azure.
- DNS records are not in code. `terraform output dns_records` lists the values; the steps are in the [runbook](../runbook.md#dns-records-at-hostpoint). They must be removed by hand during teardown (see the [README](../../README.md#how-to-tear-everything-down)).
- **Canonical host (resolved):** the apex `loetscher.io`, using an `ANAME` record at Hostpoint. See [ADR 0010](0010-apex-as-canonical-host.md).
- Other Hostpoint services on subdomains (such as webmail) must support HTTPS because of HSTS `includeSubDomains`. See [security](../security.md#warning-hsts-includesubdomains).
