# 0012: Trivy in CI as a checksum-verified pinned binary

- **Status:** Accepted
- **Date:** 2026-09-30

## Context

**Trivy** scans the Terraform code for insecure settings. The easy way to use it in GitHub Actions is the ready-made action `aquasecurity/trivy-action` (or `aquasecurity/setup-trivy`).

In March 2026 these actions were hit by a **supply-chain compromise** (an attacker changed code that many projects download and run automatically), published as advisory GHSA-69fq-xp46-6x23. A workflow that ran the compromised action could leak its secrets.

## Decision

Don't use the Trivy actions. Instead, `.github/workflows/terraform.yml`:

1. Downloads the official release file for one fixed version (`TRIVY_VERSION`, today `0.74.0`) over HTTPS.
2. Checks its **SHA-256 checksum** (a fingerprint of the file) against the value in `TRIVY_SHA256`, which was taken from the release's `trivy_<version>_checksums.txt` and cross-checked against GitHub's build-provenance attestation. If the fingerprint doesn't match, the job fails.
3. Runs `trivy config --skip-check-update --exit-code 1 .`. `--skip-check-update` uses the checks built into the pinned binary instead of downloading an unpinned checks bundle at run time. Any finding fails the job.

The Terraform checks job has only `contents: read` and no secrets.

## Consequences

Good:

- The workflow runs exactly the file that was reviewed. A changed download is rejected.
- No third-party action code runs for this step.

Bad, and how to handle it:

- Dependabot does not update this. Bump it by hand: change `TRIVY_VERSION` and `TRIVY_SHA256` together, using the SHA-256 for `trivy_<version>_Linux-64bit.tar.gz` from the release's checksums file. See the [runbook](../runbook.md#update-trivy-in-ci).
- The embedded checks only get newer when the version is bumped.
