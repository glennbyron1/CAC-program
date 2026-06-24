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
| Last Updated | June 17, 2026 (STIG CAT I review populated) |
| Assessment Period | May – June 2026 |

---

## POA&M Summary Dashboard

Update this table after each remediation cycle.

Sources:
- SCAP SCC 5.10.2 · MS_Windows_Server_2022_STIG-2.3.10 · DC01 + WS01 · scanned 2026-05-28
- SCAP SCC 5.10.2 · Microsoft_Windows_11_STIG-2.3.9 · WO02 · scanned 2026-06-02

| Risk Level | Total Findings | Remediated | Accepted Risk | Open |
|-----------|---------------|------------|---------------|------|
| CAT I (Critical) | 22 unique rules across 3 hosts | 0 | 0 (2 pending — BitLocker on WO02) | 22 |
| CAT II (High) | DC01: 110 · WS01: 111 · WO02: 122 | 0 | 0 | 343 |
| CAT III (Medium/Low) | DC01: 6 · WS01: 6 · WO02: 8 | 0 | 0 | 20 |
| **Total open** | **385** | **0** | **0** | **385** |

> **CAT I review complete (2026-06-17)** — all 22 unique CAT I rules across DC01 / WS01 / WO02 are populated below with disposition and remediation plan. Smart-card-related STIG rules (`WN22-SO-000120`, `WN22-CC-000080`, etc.) **passed** the scans — the identity authentication controls (IA-2, AC-5, IA-2(11)) are fully satisfied and not in the open-findings list. The 22 open CAT I findings are general Windows hardening gaps remediable via `Lab-Kit/Ansible/windows-stig-hardening.yml`.

---

## Open Findings

One row per finding. Copy and add rows as needed. Findings come from three sources:
- **SCC** — SCAP SCC automated STIG scan (XCCDF results in `Compliance-Reports/`)
- **STIG-V** — Manual review in DISA STIG Viewer (.ckl checklist)
- **Nessus** — Nessus Essentials credentialed vulnerability scan

### CAT I — Critical Findings

> **22 unique CAT I findings across 3 hosts**, populated 2026-06-17 from STIG Viewer .ckl review and XCCDF parse. Smart-card-related STIG rules (`WN22-SO-000120` interactive logon require smart card; `WN22-CC-000080` smart card removal behavior) **PASSED** the scans and are not in this open-findings list — they were correctly applied via `Build-CA-GPO.ps1`. The 22 open CAT I items below are general Windows hardening gaps grouped into 7 categories.

**Disposition summary (all 22 CAT I — none are false positives; all are real findings):**

| Disposition | Count | Notes |
|---|---|---|
| Open — Ansible remediation queued | 18 | Will close via `Lab-Kit/Ansible/windows-stig-hardening.yml` |
| Open — manual review required | 1 | AD data files permissions (DC-specific) |
| Open — risk-accept candidate | 2 | BitLocker disk encryption + BitLocker PIN (lab usability tradeoff) |
| Open — operational no-op, remediate anyway | 4 | WinRM Basic auth (lab uses Kerberos PSRemoting; disabling Basic has no operational impact) |
| Cleared — STIG passed | (smart-card rules above) | `WN22-SO-000120`, `WN22-CC-000080`, etc. — verified passing on all hosts |

---

#### Group 1 — AutoPlay / AutoRun (6 findings)

Common to all platforms. Real findings; registry/GPO-deliverable; remediable via Ansible playbook.

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-001 | SV-254352 | Windows Server 2022 Autoplay must be turned off for nonvolume devices | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`HKLM\...\NoAutoplayfornonVolume` = 1) |
| POA-002 | SV-254353 | Windows Server 2022 default AutoRun behavior must be configured to prevent AutoRun commands | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`NoAutorun` = 1) |
| POA-003 | SV-254354 | Windows Server 2022 AutoPlay must be disabled for all drives | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`NoDriveTypeAutoRun` = 0xFF) |
| POA-004 | SV-253386 | Windows 11 Autoplay must be turned off for non-volume devices | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (Win11 STIG variant of POA-001) |
| POA-005 | SV-253387 | Windows 11 default autorun behavior must be configured to prevent autorun commands | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (Win11 STIG variant of POA-002) |
| POA-006 | SV-253388 | Windows 11 Autoplay must be disabled for all drives | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (Win11 STIG variant of POA-003) |

#### Group 2 — Windows Installer "Always install with elevated privileges" (2 findings)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-007 | SV-254374 | Windows Server 2022 Windows Installer "Always install with elevated privileges" must be disabled | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`AlwaysInstallElevated` = 0). Privilege-escalation vector if enabled. |
| POA-008 | SV-253411 | Windows 11 "Always install with elevated privileges" must be disabled | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (Win11 STIG variant of POA-007) |

#### Group 3 — WinRM Basic Authentication (4 findings — operational no-op)

The lab uses **Kerberos** for PowerShell Remoting (proven during the v1.2 build session: `Invoke-Command -ComputerName Lab-DC01` worked with domain credentials; PowerShell Direct over the hypervisor channel also worked). Disabling Basic auth has **no operational impact** but should still be remediated for hardening completeness.

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-009 | SV-254378 | Windows Server 2022 WinRM client must not use Basic authentication | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`AllowBasic` = 0). No operational impact — lab uses Kerberos. |
| POA-010 | SV-254381 | Windows Server 2022 WinRM service must not use Basic authentication | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Same as POA-009 (service-side counterpart) |
| POA-011 | SV-253416 | Windows 11 WinRM client must not use Basic authentication | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Win11 STIG variant of POA-009 |
| POA-012 | SV-253418 | Windows 11 WinRM service must not use Basic authentication | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Win11 STIG variant of POA-010 |

#### Group 4 — Anonymous Enumeration of Shares (2 findings)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-013 | SV-254467 | Windows Server 2022 must not allow anonymous enumeration of shares | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`RestrictNullSessAccess` = 1) |
| POA-014 | SV-253454 | Windows 11 anonymous enumeration of shares must be restricted | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Win11 STIG variant of POA-013 |

#### Group 5 — LAN Manager Authentication Level (2 findings)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-015 | SV-254475 | Windows Server 2022 LAN Manager authentication level must be configured to send NTLMv2 response only / refuse LM and NTLM | SCC | LAB-DC01 / LAB-WS01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`LmCompatibilityLevel` = 5). Modern Windows is NTLMv2-by-default but STIG checks explicit policy. |
| POA-016 | SV-253462 | Windows 11 LanMan authentication level must be set to send NTLMv2 response only, and to refuse LM and NTLM | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Win11 STIG variant of POA-015 |

#### Group 6 — AD Data Files Permissions (1 finding — DC-specific manual review)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-017 | SV-254391 | Windows Server 2022 permissions on the Active Directory data files must only allow System and Administrators access | SCC | LAB-DC01 | 2026-05-28 | Q3 2026 | Glenn Byron | Open | **Manual review required**: verify ACLs on `%SYSTEMROOT%\NTDS\*` directly on Lab-DC01. Not safely automatable; over-tight permissions can break AD replication. Will validate during the Ansible STIG hardening pass and document the ACLs in the SAR. |

#### Group 7 — Windows 11 Specific (5 findings)

| ID | STIG Rule ID | Finding Title | Source | System | Discovery Date | Scheduled Completion | Responsible Party | Status | Notes |
|----|-----------------|---------------|--------|--------|----------------|---------------------|------------------|--------|-------|
| POA-018 | SV-253259 | Windows 11 information systems must use BitLocker to encrypt all disks | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open — risk-accept candidate | WO02 has TPM 2.0 so BitLocker is feasible. **Risk-accept rationale (lab):** no production data on WO02; physical access controlled (residential office). Compensating controls: smart-card-required logon + 2-second `ScRemoveOption` lock + Hyper-V host BitLocker (where lab VMs live). Moving to Risk Acceptance Register pending decision. |
| POA-019 | SV-253260 | Windows 11 systems must use a BitLocker PIN for pre-boot authentication | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open — risk-accept candidate | TPM-only vs TPM+PIN tradeoff. Common federal risk-accept with documented operational rationale. Pending Risk Acceptance Register entry. |
| POA-020 | SV-253283 | Windows 11 Data Execution Prevention (DEP) must be configured to at least OptOut | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`bcdedit /set nx OptOut`). |
| POA-021 | SV-253284 | Windows 11 Structured Exception Handling Overwrite Protection (SEHOP) must be enabled | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`DisableExceptionChainValidation` = 0). |
| POA-022 | SV-253382 | Windows 11 Solicited Remote Assistance must not be allowed | SCC | WO02 | 2026-06-02 | Q3 2026 | Glenn Byron | Open | Ansible remediation queued (`fAllowToGetHelp` = 0). |

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
| RA-001 | BitLocker disk encryption on WO02 (SV-253259) | CAT I | Lab environment with no production data; BitLocker key escrow process for federal deployment requires AD recovery key infrastructure not in scope for this lab tier | Smart-card-required interactive logon (scforceoption=1); 2-second session lock on card removal (ScRemoveOption=1); physical access controlled (residential office); Hyper-V host where lab VMs live runs BitLocker | Glenn Byron (System Owner / Self-Assessed Lab AO) | [Pending decision] | Annual review 2027-05 |
| RA-002 | BitLocker pre-boot PIN on WO02 (SV-253260) | CAT I | TPM-only vs TPM+PIN is a documented federal risk-accept pattern; TPM-only provides tamper-evidence; pre-boot PIN is operational-burden tradeoff for kiosk/shared-workstation scenarios | TPM 2.0 provides tamper-evidence; Smart-card-required logon at OS boundary; physical access control | Glenn Byron | [Pending decision] | Annual review 2027-05 |

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
| STIG Viewer manual CAT I review complete | 2026-06-17 | Glenn Byron | [x] |
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
| 1.1 | June 17, 2026 | Glenn Byron | STIG Viewer CAT I review: all 22 unique CAT I findings across DC01 / WS01 / WO02 populated with disposition and remediation plan. Confirmed smart-card-related STIG rules (`WN22-SO-000120`, `WN22-CC-000080`) passed the scans (identity controls IA-2 / AC-5 / IA-2(11) fully satisfied). Risk Acceptance Register seeded with two pending entries (RA-001 BitLocker disk encryption, RA-002 BitLocker pre-boot PIN). Dashboard updated with WO02 Win11 STIG numbers. |

---

*Related documents: `SSP-Template.md`, `SAR-Template.md`,
`Compliance-Reports/README.md`. See `ROADMAP.md Phase 5` for the full ATO package checklist.*
