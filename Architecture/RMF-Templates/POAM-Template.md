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
| Date Prepared | [FILL IN] |
| Last Updated | [FILL IN] |
| Assessment Period | [FILL IN — e.g., May 2026] |

---

## POA&M Summary Dashboard

Update this table after each remediation cycle.

| Risk Level | Total Findings | Remediated | Accepted Risk | Open |
|-----------|---------------|------------|---------------|------|
| CAT I (Critical) | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] |
| CAT II (High) | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] |
| CAT III (Medium/Low) | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] |
| **Total** | | | | |

---

## Open Findings

One row per finding. Copy and add rows as needed. Findings come from three sources:
- **SCC** — SCAP SCC automated STIG scan (XCCDF results in `Compliance-Reports/`)
- **STIG-V** — Manual review in DISA STIG Viewer (.ckl checklist)
- **Nessus** — Nessus Essentials credentialed vulnerability scan

### CAT I — Critical Findings

| ID | STIG / Plugin ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-001 | [FILL IN] | [FILL IN] | SCC / STIG-V / Nessus | [FILL IN hostname] | [FILL IN] | [FILL IN] | [FILL IN] | Open | [FILL IN — remediation plan or risk acceptance rationale] |

### CAT II — High Findings

| ID | STIG / Plugin ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-002 | [FILL IN] | [FILL IN] | SCC / STIG-V / Nessus | [FILL IN hostname] | [FILL IN] | [FILL IN] | [FILL IN] | Open | |

### CAT III — Medium / Low Findings

| ID | STIG / Plugin ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-003 | [FILL IN] | [FILL IN] | SCC / STIG-V / Nessus | [FILL IN hostname] | [FILL IN] | [FILL IN] | [FILL IN] | Open | |

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
| Phase 4 SCAP SCC scans complete | [FILL IN] | [FILL IN] | [ ] |
| Phase 4 Nessus scans complete | [FILL IN] | [FILL IN] | [ ] |
| Initial POA&M populated from scan results | [FILL IN] | Glenn Byron | [ ] |
| CAT I findings remediated or risk accepted | [FILL IN] | [FILL IN] | [ ] |
| CAT II findings remediated or risk accepted | [FILL IN] | [FILL IN] | [ ] |
| SSP finalized and submitted to AO | [FILL IN] | Glenn Byron | [ ] |
| ATO decision received | [FILL IN] | [FILL IN AO Name] | [ ] |
| First annual re-assessment (continuous monitoring) | [FILL IN — ~1 year from ATO] | [FILL IN] | [ ] |

---

## Document Control

| Version | Date | Author | Change Summary |
|---------|------|--------|----------------|
| 0.1 | [FILL IN] | Glenn Byron | Initial template created |
| 1.0 | [FILL IN] | [FILL IN] | Populated with Phase 4 scan results |

---

*Related documents: `Architecture/SSP-Template.md`, `Architecture/SAR-Template.md`,
`Compliance-Reports/README.md`. See `ROADMAP.md Phase 5` for the full ATO package checklist.*
