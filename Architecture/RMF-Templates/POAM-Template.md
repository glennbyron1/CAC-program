# Plan of Action & Milestones (POA&M)

Document ID: ARCH-ICAM-007
Author: Glenn Byron
Framework: NIST SP 800-53 Rev. 5 CA-5 | NIST SP 800-37 Rev. 2 | DISA RMF

> **How to use this template:** Add a row for every open finding from your SCAP SCC STIG scans
> and Nessus Essentials results. Update the Status column as findings are remediated. The AO
> reviews this document before granting an ATO — every open Critical finding must either be
> remediated or have a documented risk acceptance before authorization is granted.
>
> Risk Levels follow DISA CAT designations: CAT I = Critical, CAT II = High, CAT III = Medium/Low.

---

## System Information

| Field | Value |
|-------|-------|
| System Name | Enterprise CAC/PIV ICAM System |
| Document ID | ARCH-ICAM-007 |
| Prepared By | Glenn Byron |
| Date Prepared | June 1, 2026 |
| Last Updated | June 1, 2026 |
| Assessment Period | May – June 2026 |

---

## POA&M Summary Dashboard

Update this table after each remediation cycle.

Source: SCAP SCC 5.10.2 · MS_Windows_Server_2022_STIG-2.3.10 · 2026-05-28

| Risk Level | Total Findings | Remediated | Accepted Risk | Open |
|-----------|---------------|------------|---------------|------|
| CAT I (Critical) | 9 per VM (18 total) | 0 | 0 | 18 |
| CAT II (High) | DC01: 110 / WS01: 111 | 0 | 0 | 221 |
| CAT III (Medium/Low) | 6 per VM (12 total) | 0 | 0 | 12 |
| **Total** | **251** | **0** | **0** | **251** |

> Note: These findings are Windows Server 2022 STIG items unrelated to the identity
> authentication controls (IA-2, AC-5, etc.) which are fully satisfied. Full STIG
> hardening via `Lab-Kit/Ansible/windows-stig-hardening.yml` is the remediation plan.

---

## Open Findings

One row per finding. Copy and add rows as needed. Findings come from three sources:
- **SCC** — SCAP SCC automated STIG scan (XCCDF results in `Compliance-Reports/`)
- **STIG-V** — Manual review in DISA STIG Viewer (.ckl checklist)
- **Nessus** — Nessus Essentials credentialed vulnerability scan

### CAT I — Critical Findings

> 9 CAT I findings on each VM (DC01 and WS01). Individual STIG Rule IDs are available
> in the XCCDF results at `Compliance-Reports/After-MFA/DC01-SCAP-Raw/` and
> `Compliance-Reports/After-MFA/WS01-SCAP-Raw/`. Open the .ckl files in DISA STIG Viewer
> to see the full list with finding titles. Representative entries below — populate the
> remainder from STIG Viewer.

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-001 | WN22-SO-000120 | Interactive logon: Require smart card — must be enabled | SCC | LAB-DC01 / LAB-WORKSTATION01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Remediated on WS01 via GPO; DC01 intentionally excluded (scforceoption=1 on DC locks all logins) |
| POA-002 | WN22-CC-000080 | Smart card removal behavior must be configured | SCC | LAB-DC01 / LAB-WORKSTATION01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Applied via Build-CA-GPO.ps1; verify STIG rule ID matches GPO setting |
| POA-003 | [See XCCDF XML] | Remaining 7 CAT I findings per VM | SCC | LAB-DC01 / LAB-WORKSTATION01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Full list in STIG Viewer from .ckl files; remediation via Ansible STIG hardening playbook |

### CAT II — High Findings

> DC01: 110 open · WS01: 111 open. Full list in STIG Viewer from .ckl files.
> Bulk remediation via `Lab-Kit/Ansible/windows-stig-hardening.yml`.

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-004 | [See XCCDF XML] | 110 / 111 CAT II findings — see STIG Viewer | SCC | LAB-DC01 / LAB-WORKSTATION01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Bulk remediation planned via Ansible STIG hardening playbook |

### CAT III — Medium / Low Findings

> 6 open per VM. Low priority; address after CAT I/II remediation.

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-005 | [See XCCDF XML] | 6 CAT III findings per VM — see STIG Viewer | SCC | LAB-DC01 / LAB-WORKSTATION01 | 2026-05-28 | Q4 2026 | Glenn Byron | Open | Low priority; address after CAT I/II remediation |

---

## Closed / Remediated Findings

Move findings here once remediation is confirmed by a follow-up SCAP SCC scan or STIG Viewer re-check.

| ID | STIG / Plugin ID | Finding Title | Risk Level | Remediation Action | Closure Date | Verified By |
|----|-----------------|---------------|------------|-------------------|--------------|-------------|
| | | | | | | |

---

## Risk Acceptance Register

Use this section for findings that cannot be remediated within the authorization period and where
residual risk is formally accepted by the system owner or AO.

| ID | Finding Title | Risk Level | Reason Cannot Remediate | Compensating Controls | Risk Accepted By | Acceptance Date | Expiration |
|----|--------------|------------|------------------------|----------------------|-----------------|-----------------|------------|
| | | | | | | | |

---

## Remediation Notes

### Common STIG Findings for This Environment

The following are findings commonly flagged in Windows Server 2022 and AD DS STIG scans that this
program's hardening scripts address. Check off as confirmed remediated by your post-hardening scan.

| STIG Rule ID | Finding | Remediated By | Confirmed |
|-------------|---------|---------------|-----------|
| WN22-CC-000080 | Smart card removal policy must be configured | `Build-CA-GPO.ps1` — ScRemoveOption = 1 | [ ] |
| WN22-SO-000120 | Interactive logon: require smart card | `Group-Policy/Enforce-SmartCard.ps1` — scforceoption = 1 | [ ] |
| WN22-AU-000050 | Audit logon events must be enabled | `Build-CAC-Lab.ps1` audit policy configuration | [ ] |
| WN22-CC-000210 | WDigest Authentication must be disabled | GPO — registry: `UseLogonCredential = 0` | [ ] |
| [Add others from your scan results] | | | |

---

## Milestone Schedule

| Milestone | Target Date | Owner | Status |
|-----------|-------------|-------|--------|
| Before-MFA SCAP SCC scans complete | 2026-05-27 | Glenn Byron | [x] |
| After-MFA SCAP SCC scans complete | 2026-05-28 | Glenn Byron | [x] |
| Initial POA&M populated from scan results | 2026-06-01 | Glenn Byron | [x] |
| Nessus Essentials credentialed scan | Q3 2026 | Glenn Byron | [ ] |
| STIG Viewer manual CAT I review complete | Q3 2026 | Glenn Byron | [ ] |
| Ansible STIG hardening playbook run (CAT I/II remediation) | Q3 2026 | Glenn Byron | [ ] |
| Post-remediation SCAP scan to verify improvements | Q3 2026 | Glenn Byron | [ ] |
| CAT I findings remediated or risk accepted | Q3 2026 | Glenn Byron | [ ] |
| SSP finalized | Q3 2026 | Glenn Byron | [ ] |
| ATO decision | Q4 2026 | TBD (AO) | [ ] |
| First annual re-assessment | May 2027 | Glenn Byron | [ ] |

---

## Document Control

| Version | Date | Author | Change Summary |
|---------|------|--------|----------------|
| 0.1 | May 2026 | Glenn Byron | Initial template created |
| 1.0 | June 1, 2026 | Glenn Byron | Populated with Before/After-MFA SCAP SCC scan results |

---

*Related documents: `Architecture/SSP-Template.md`, `Architecture/SAR-Template.md`,
`Compliance-Reports/README.md`. See `ROADMAP.md Phase 5` for the full ATO package checklist.*
