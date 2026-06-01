# Compliance Reports

**Author:** Glenn Byron

This folder tracks the before/after compliance posture of the lab as it is
hardened, using free, publicly available DoD and federal tools. It is part of
the Federal Compliance / Testing track — see
[`../Architecture/STIG-Hardening-Guide.md`](../Architecture/STIG-Hardening-Guide.md)
for the full runbook and
[`../Stage-Reports.ps1`](../Stage-Reports.ps1) for the staging utility.

## Structure

```text
Compliance-Reports/
├── README.md                                              <-- this file (scoring summary table below)
├── Before-MFA/
│   ├── DC01-SCC-Summary-2026-05-27.html                  <-- SCC summary viewer, DC01 baseline
│   ├── DC01-AllSettings-WinServer2022-STIG-2026-05-27.html
│   ├── DC01-NonCompliance-WinServer2022-STIG-2026-05-27.html
│   ├── DC01-SCAP-Raw/                                    <-- XCCDF XML + CKL checklist
│   ├── WS01-SCC-Summary-2026-05-27.html                  <-- SCC summary viewer, WS01 baseline
│   ├── WS01-AllSettings-WinServer2022-STIG-2026-05-27.html
│   ├── WS01-NonCompliance-WinServer2022-STIG-2026-05-27.html
│   ├── WS01-SCAP-Raw/                                    <-- XCCDF XML + CKL checklist
│   ├── Before-MFA-DC01-Results.zip                       <-- raw SCC session archive
│   └── Before-MFA-WS01-Results.zip                       <-- raw SCC session archive
└── After-MFA/
    ├── DC01-SCC-Summary-2026-05-28.html                  <-- SCC summary viewer, DC01 hardened
    ├── DC01-AllSettings-WinServer2022-STIG-2026-05-28.html
    ├── DC01-NonCompliance-WinServer2022-STIG-2026-05-28.html
    ├── DC01-SCAP-Raw/                                    <-- XCCDF XML + CKL checklist
    ├── WS01-SCC-Summary-2026-05-28.html                  <-- SCC summary viewer, WS01 hardened
    ├── WS01-AllSettings-WinServer2022-STIG-2026-05-28.html
    ├── WS01-NonCompliance-WinServer2022-STIG-2026-05-28.html
    └── WS01-SCAP-Raw/                                    <-- XCCDF XML + CKL checklist
```

## How reports get here

1. Run a SCAP Compliance Checker (SCC) scan on the lab VM.
2. `..\Stage-Reports.ps1 -Stage Before` stages the Before-MFA results.
3. Apply hardening (smart-card GPOs, STIG hardening), restart, rescan.
4. `..\Stage-Reports.ps1 -Stage After` stages the After-MFA results.
5. Add ACAS / Nessus PDF exports to the matching folder when available.

## Scoring Summary

Tool: SCAP Compliance Checker (SCC) 5.10.2 · Benchmark: MS_Windows_Server_2022_STIG-2.3.10
Scan date: Before-MFA 2026-05-27 · After-MFA 2026-05-28

| VM | Audit Stage | SCAP Score | CAT I Fail | CAT II Fail | CAT III Fail |
| :--- | :--- | :--- | :--- | :--- | :--- |
| DC01 | Before-MFA (baseline) | 44.95% | 9 | 105 | 6 |
| DC01 | After-MFA (smart card enforced) | 42.66% | 9 | 110 | 6 |
| WS01 | Before-MFA (baseline) | 42.20% | 9 | 111 | 6 |
| WS01 | After-MFA (smart card enforced) | 42.20% | 9 | 111 | 6 |

### Interpretation

The Before/After-MFA scans establish the STIG compliance baseline and confirm the
state of the lab before and after smart-card enforcement was applied. The scores
are similar across both stages because the smart-card hardening phase targeted the
**Identity authentication pillar** (NIST IA-2, IA-5) — not a full STIG hardening pass.

The CAT I failures remaining (9 per VM) are a mix of authentication-adjacent and
broader server hardening findings. A full STIG hardening pass using
`Lab-Kit/Ansible/windows-stig-hardening.yml` would address the CAT II/III findings
systematically. That is scoped as the next compliance phase.

**ACAS / Nessus scans:** Pending — will be added to each folder when run.

## Note on contents

Only sanitized, lab-generated reports belong here. Do not commit reports
containing real organizational hostnames, IP addresses, or user accounts —
run `..\Scrub-Repo.ps1 -WhatIf` before pushing. Raw `.nessus` packages and
multi-megabyte exports should be reviewed for sensitive content before they
are committed; the repository `.gitignore` already blocks common key/cert and
VM artifacts.
