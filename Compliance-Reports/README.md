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
├── After-MFA/
│   ├── DC01-SCC-Summary-2026-05-28.html                  <-- SCC summary viewer, DC01 hardened
│   ├── DC01-AllSettings-WinServer2022-STIG-2026-05-28.html
│   ├── DC01-NonCompliance-WinServer2022-STIG-2026-05-28.html
│   ├── DC01-SCAP-Raw/                                    <-- XCCDF XML + CKL checklist
│   ├── WS01-SCC-Summary-2026-05-28.html                  <-- SCC summary viewer, WS01 hardened
│   ├── WS01-AllSettings-WinServer2022-STIG-2026-05-28.html
│   ├── WS01-NonCompliance-WinServer2022-STIG-2026-05-28.html
│   └── WS01-SCAP-Raw/                                    <-- XCCDF XML + CKL checklist
└── Laptop/                                                <-- WO02 physical endpoint (Windows 11)
    ├── Before-SmartCard/                                 <-- (empty - no baseline taken before enrollment)
    └── After-SmartCard/
        └── 2026-06-02_104513/                            <-- full SCC session folder, Win11 STIG 2.3.9
            ├── SCC_Summary_Viewer_2026-06-02_104513.html
            ├── Logs/                                     <-- scan error/warning log
            └── Results/SCAP/
                ├── *_All-Settings_Microsoft_Windows_11_STIG-2.3.9.html
                ├── *_Non-Compliance_Microsoft_Windows_11_STIG-2.3.9.html
                ├── Checklists/*.ckl                      <-- STIG Viewer checklist
                └── XML/                                  <-- XCCDF / OVAL / OCIL result XML
```

## How reports get here

1. Run a SCAP Compliance Checker (SCC) scan on the lab VM.
2. `..\Stage-Reports.ps1 -Stage Before` stages the Before-MFA results.
3. Apply hardening (smart-card GPOs, STIG hardening), restart, rescan.
4. `..\Stage-Reports.ps1 -Stage After` stages the After-MFA results.
5. Add ACAS / Nessus PDF exports to the matching folder when available.

## Scoring Summary

Tools: SCAP Compliance Checker (SCC) 5.10.2
Benchmarks: `MS_Windows_Server_2022_STIG-2.3.10` (DC01/WS01) · `Microsoft_Windows_11_STIG-2.3.9` (WO02 laptop)
Scan dates: Before-MFA 2026-05-27 · After-MFA 2026-05-28 · WO02 Laptop 2026-06-02

| Host | Benchmark | Audit Stage | SCAP Score | CAT I Fail | CAT II Fail | CAT III Fail |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| DC01 | Server 2022 STIG 2.3.10 | Before-MFA (baseline) | 44.95% | 9 | 105 | 6 |
| DC01 | Server 2022 STIG 2.3.10 | After-MFA (smart card enforced) | 42.66% | 9 | 110 | 6 |
| WS01 | Server 2022 STIG 2.3.10 | Before-MFA (baseline) | 42.20% | 9 | 111 | 6 |
| WS01 | Server 2022 STIG 2.3.10 | After-MFA (smart card enforced) | 42.20% | 9 | 111 | 6 |
| WO02 | **Windows 11 STIG 2.3.9** | **After-SmartCard (laptop, domain-joined)** | **37.00%** | **13** | **122** | **8** |

### Interpretation

**DC01 / WS01 (VMs, Server 2022 STIG):** The Before/After-MFA scans establish the STIG compliance baseline and confirm the state of the lab before and after smart-card enforcement was applied. The scores are similar across both stages because the smart-card hardening phase targeted the **Identity authentication pillar** (NIST IA-2, IA-5) — not a full STIG hardening pass.

The CAT I failures remaining (9 per VM) are a mix of authentication-adjacent and broader server hardening findings. A full STIG hardening pass using `Lab-Kit/Ansible/windows-stig-hardening.yml` would address the CAT II/III findings systematically. That is scoped as the next compliance phase.

> **POA&M CAT I review complete (2026-06-17):** All 22 unique CAT I findings across DC01 / WS01 / WO02 are populated in [`Architecture/RMF-Templates/POAM-Template.md`](../Architecture/RMF-Templates/POAM-Template.md) grouped into 7 categories (AutoPlay ×6, Windows Installer elevated ×2, WinRM Basic auth ×4, Anonymous share enumeration ×2, LM auth level ×2, AD data files permissions ×1, Win11-specific ×5). Disposition: 18 queued for Ansible remediation, 1 manual review (AD data files — DC-specific), 2 risk-accept candidates (BitLocker on WO02), 4 operational no-op but remediate anyway (WinRM Basic — lab uses Kerberos). **Smart-card STIG rules `WN22-SO-000120` and `WN22-CC-000080` passed the scans — the identity authentication controls (IA-2 / IA-2(11) / AC-5) are fully satisfied and are NOT in the open-findings list.**

> **IIS STIG assessment complete (2026-06-24):** scanned LAB-DC01 IIS 10.0 CRL/AIA endpoint against IIS Server STIG 3.2.9 (53.85% score) + Site STIG 2.10.10 (54.55% score). Results in [`Compliance-Reports/IIS-STIG/`](IIS-STIG/). **Headline finding (POA-024 / SV-218821 HTTPS-required): Risk Accept** with RFC 5280 §4.2.1.13 rationale — HTTP-only CRL distribution is the standard federal pattern. 27 fails total (2 CAT I + 23 CAT II + 2 CAT III) populated in POA&M with disposition for each; ~6 findings are N/A or Risk Accept because they apply to SSL/TLS/cookies/client-auth which a public CRL endpoint does not use by design.

**WO02 (physical laptop, Windows 11 STIG):** This is a single-stage scan — there's no pre-enrollment baseline because the laptop was scanned only after smart card enrollment was complete. The 37.00% score against the Windows 11 STIG (258 rules total, MAC-1 Classified profile) is consistent with a domain-joined Windows 11 endpoint that has received **only the smart card GPO** — no broader STIG-aligned hardening yet. The 13 CAT I findings are split between authentication-adjacent (which the smart card GPO addresses) and Windows 11 client-specific items (BitLocker, AppLocker, secure boot, Defender exclusions) that require additional GPO scope. The 31 not-checked items are SCAP **manual questions** that need to be filled in via a Manual Question Auto-Answer template in SCC — they are valid checks, just deferred to STIG Viewer review.

> **Note:** The WO02 scan was run against the highest-rigor profile (`MAC-1_Classified`). The same scan run against `MAC-3_Sensitive` would score higher; the choice was deliberate to show worst-case posture.

**ACAS / Nessus scans:** Pending — will be added to each folder when run.

## Note on contents

Only sanitized, lab-generated reports belong here. Do not commit reports
containing real organizational hostnames, IP addresses, or user accounts —
run `..\Scrub-Repo.ps1 -WhatIf` before pushing. Raw `.nessus` packages and
multi-megabyte exports should be reviewed for sensitive content before they
are committed; the repository `.gitignore` already blocks common key/cert and
VM artifacts.
