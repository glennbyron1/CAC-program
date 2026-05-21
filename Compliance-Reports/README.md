# Compliance Reports

**Author:** Glenn Byron

This folder tracks the before/after compliance posture of the lab as it is
hardened, using free, publicly available DoD and federal tools. It is part of
the optional Federal Compliance / Testing track — see
[`../Architecture/STIG-Hardening-Guide.md`](../Architecture/STIG-Hardening-Guide.md)
for the full runbook and
[`../Stage-Reports.ps1`](../Stage-Reports.ps1) for the staging utility.

## Structure

```text
Compliance-Reports/
├── README.md                       <-- this file (scoring summary table below)
├── Before-MFA/
│   ├── Baseline-Report.html        <-- SCAP STIG report, pre-hardening
│   └── Baseline-Vulnerability.pdf  <-- ACAS / Nessus baseline scan
└── After-MFA/
    ├── Hardened-Report.html        <-- SCAP STIG report, post-hardening
    └── Hardened-Vulnerability.pdf  <-- ACAS / Nessus hardened scan
```

## How reports get here

1. Run a SCAP Compliance Checker (SCC) scan on the clean lab VM.
2. `..\Stage-Reports.ps1 -Stage Before` (or run it and choose option 1).
3. Apply the hardening (lab build scripts + smart-card GPOs), restart, rescan.
4. `..\Stage-Reports.ps1 -Stage After` (or choose option 2).
5. Add the ACAS / Nessus PDF exports to the matching folder.
6. Update the scoring table below with your real lab numbers.

## Scoring Summary

Replace the example figures with your actual lab results.

| Audit Stage | SCAP STIG Score | ACAS Critical / High | Target Security Tier |
| :--- | :--- | :--- | :--- |
| Initial Baseline (Before MFA) | _e.g._ 42.1% Compliance | _e.g._ 18 Open Critical / High | Vulnerable Topology |
| Hardened Infrastructure (After MFA) | _e.g._ 94.6% Compliance | _e.g._ 0 Open Critical / High | Audit-Ready Baseline |

## Note on contents

Only sanitized, lab-generated reports belong here. Do not commit reports
containing real organizational hostnames, IP addresses, or user accounts —
run `..\Scrub-Repo.ps1 -WhatIf` before pushing. Raw `.nessus` packages and
multi-megabyte exports should be reviewed for sensitive content before they
are committed; the repository `.gitignore` already blocks common key/cert and
VM artifacts.
