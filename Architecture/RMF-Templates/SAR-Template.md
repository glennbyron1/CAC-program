# Security Assessment Report (SAR)

Document ID: ARCH-ICAM-008
Author: Glenn Byron
Framework: NIST SP 800-53 Rev. 5 CA-2 | NIST SP 800-37 Rev. 2 | DISA RMF Assess Phase

> **How to use this template:** This document summarizes the results of Phase 4 STIG and
> vulnerability assessments. Complete it after all SCAP SCC scans, STIG Viewer checklist reviews,
> and Nessus Essentials scans are finished. The SAR feeds directly into the POA&M
> (`Architecture/POAM-Template.md`) and SSP (`Architecture/SSP-Template.md`) for the ATO package.

---

## 1. Document Information

| Field | Value |
|-------|-------|
| System Name | Enterprise CAC/PIV ICAM System |
| Document ID | ARCH-ICAM-008 |
| Assessment Period | [FILL IN — e.g., May – June 2026] |
| Assessor | Glenn Byron |
| Assessment Type | Self-assessment (independent assessment recommended for production ATO) |
| Report Date | [FILL IN] |
| Version | 1.0 |

---

## 2. Executive Summary

> Write this section last, after populating all the findings tables.

This Security Assessment Report documents the findings from the RMF Assess phase for the
Enterprise CAC/PIV ICAM system. The assessment included automated DISA STIG scans using the
SCAP Compliance Checker (SCC), manual checklist review using DISA STIG Viewer, and credentialed
vulnerability scanning using Nessus Essentials.

**Before Hardening:**
The baseline scan of the clean Windows Server VM showed a SCAP STIG compliance score of
[FILL IN]%, with [FILL IN] CAT I and [FILL IN] CAT II findings. Nessus identified [FILL IN]
Critical and [FILL IN] High vulnerabilities.

**After Hardening:**
Following deployment of the lab build scripts (`Build-CAC-Lab.ps1`, `Build-CA-GPO.ps1`) and
smart card enforcement GPOs, the post-hardening scan showed [FILL IN]% compliance, with
[FILL IN] remaining open CAT I findings and [FILL IN] CAT II findings. Nessus showed [FILL IN]
Critical and [FILL IN] High vulnerabilities remaining.

**Overall Risk Determination:** [FILL IN — Low / Moderate / High]

**Recommendation:** [FILL IN — Recommend ATO with conditions / Recommend ATO / Deny ATO]

---

## 3. Assessment Scope

### 3.1 Systems Assessed

| System | Hostname | OS | Assessment Date |
|--------|----------|----|-----------------|
| Domain Controller / Issuing CA host | [FILL IN] | Windows Server 2022 | [FILL IN] |
| HTTP CRL / AIA Server | [FILL IN] | Windows Server 2022 / IIS 10.0 | [FILL IN] |
| Admin Workstation | [FILL IN] | Windows 11 | [FILL IN] |
| [Additional systems] | | | |

### 3.2 STIGs Assessed

| STIG | Version | Assessment Method | Checklist File |
|------|---------|------------------|----------------|
| Microsoft Windows Server 2022 STIG | V2R2 (or current) | SCAP SCC + STIG Viewer manual review | `Compliance-Reports/After-MFA/WinServer2022-STIG.ckl` |
| Active Directory Domain Services STIG | V3R2 (or current) | STIG Viewer manual review | `Compliance-Reports/After-MFA/AD-DS-STIG.ckl` |
| PKI / Certificate Services STIG | V2R1 (or current) | STIG Viewer manual review | `Compliance-Reports/After-MFA/PKI-CS-STIG.ckl` |
| IIS 10.0 Site STIG | V3R1 (or current) | STIG Viewer manual review | `Compliance-Reports/After-MFA/IIS10-STIG.ckl` |

### 3.3 Vulnerability Scanner

| Tool | Version | Scan Type | Plugin Feed Date |
|------|---------|-----------|-----------------|
| Nessus Essentials | [FILL IN] | Credentialed Windows scan | [FILL IN] |

---

## 4. Assessment Methodology

All assessments followed the procedures documented in `Architecture/FedGov-Tools-Setup-Guide.md`
and `Architecture/STIG-Hardening-Guide.md`.

1. **Baseline scan** — SCAP SCC scan on a clean, un-hardened Windows Server VM to establish a before state. Results staged to `Compliance-Reports/Before-MFA/` using `Stage-Reports.ps1`.

2. **Hardening** — Applied `Build-CAC-Lab.ps1`, `Build-CA-GPO.ps1`, and smart card enforcement GPOs. Rebooted the VM to flush Group Policy.

3. **Post-hardening scan** — Re-ran SCAP SCC scan. Results staged to `Compliance-Reports/After-MFA/`.

4. **STIG Viewer review** — Imported XCCDF results from SCC into DISA STIG Viewer. Completed manual review of CAT I and CAT II findings not covered by SCAP automation. Exported .ckl checklists.

5. **Nessus scans** — Ran credentialed scans before and after hardening. Documented all Critical and High findings.

---

## 5. SCAP SCC Scan Results

### 5.1 Before / After Compliance Score Comparison

| System | STIG | Before Score | After Score | Delta |
|--------|------|-------------|------------|-------|
| [FILL IN hostname] | Windows Server 2022 | [FILL IN]% | [FILL IN]% | +[FILL IN]% |
| [FILL IN hostname] | IIS 10.0 | [FILL IN]% | [FILL IN]% | +[FILL IN]% |

### 5.2 Findings by Category (Post-Hardening)

| STIG | CAT I Open | CAT II Open | CAT III Open | Not Applicable | Not Reviewed |
|------|-----------|------------|-------------|----------------|--------------|
| Windows Server 2022 | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] |
| IIS 10.0 | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] |

---

## 6. Manual STIG Viewer Findings

List findings that required manual review (not automated by SCAP). These are typically
CAT I findings related to physical access, organizational policy, or configurations
that SCAP cannot check remotely.

| STIG Rule ID | Category | Finding Title | System | Status | Disposition |
|-------------|---------|---------------|--------|--------|-------------|
| [FILL IN] | CAT I | [FILL IN] | [FILL IN] | [Open / Fixed / N/A] | [Remediated / Risk Accepted / Operational Requirement] |
| [FILL IN] | CAT II | [FILL IN] | [FILL IN] | [Open / Fixed / N/A] | |

---

## 7. Nessus Vulnerability Scan Results

### 7.1 Finding Count Comparison

| Scan Stage | Critical | High | Medium | Low | Info |
|-----------|---------|------|--------|-----|------|
| Before Hardening | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] |
| After Hardening | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] | [FILL IN] |

### 7.2 Critical and High Findings (Post-Hardening)

> Only list remaining open findings after hardening. Remediated findings do not need to appear here.

| Plugin ID | Severity | Finding Title | Affected Host | Remediation Action | Status |
|-----------|---------|---------------|---------------|-------------------|--------|
| [FILL IN] | Critical | [FILL IN] | [FILL IN] | [FILL IN] | Open / Remediated |
| [FILL IN] | High | [FILL IN] | [FILL IN] | [FILL IN] | Open / Remediated |

---

## 8. Controls Assessment Summary

Summary of SP 800-53 control testing results from the assessment activities.

| Control | Title | Assessment Result | Method | Notes |
|---------|-------|------------------|--------|-------|
| IA-2 | Identification and Authentication | [Satisfied / Partially Satisfied / Not Satisfied] | SCAP SCC + Manual | |
| IA-2(11) | Workstation Hardware Token Logon | [Satisfied / Partially Satisfied / Not Satisfied] | SCAP SCC + GPO review | |
| AC-11 | Session Lock | [Satisfied / Partially Satisfied / Not Satisfied] | SCAP SCC + Manual | |
| AC-5 | Separation of Duties | [Satisfied / Partially Satisfied / Not Satisfied] | Manual / Procedural | |
| AC-17 | Remote Access | [Satisfied / Partially Satisfied / Not Satisfied] | Manual — VPN EAP-TLS test | |
| SC-8 | Transmission Confidentiality | [Satisfied / Partially Satisfied / Not Satisfied] | Manual — IPsec policy review | |
| SC-17 | PKI Certificates | [Satisfied / Partially Satisfied / Not Satisfied] | Manual — CA audit | |
| CA-2 | Security Assessments | Satisfied | This assessment | |
| AU-2 | Event Logging | [Satisfied / Partially Satisfied / Not Satisfied] | Manual — AD CS audit log | |

---

## 9. Risk Summary

### 9.1 Overall Risk Rating

| Category | Finding Count | Risk Contribution |
|---------|--------------|------------------|
| CAT I (Critical) — Unmitigated | [FILL IN] | HIGH |
| CAT II (High) — Unmitigated | [FILL IN] | MODERATE |
| CAT III (Medium/Low) — Unmitigated | [FILL IN] | LOW |

**Overall Residual Risk:** [FILL IN — Low / Moderate / High]

Residual risk is acceptable because: [FILL IN — e.g., compensating controls in place, all CAT I findings remediated, etc.]

### 9.2 Key Risk Factors

[FILL IN — describe the 2-3 most significant risk factors remaining after hardening. Example:
"The primary residual risk is the software-based key storage for CA private keys (SC-28). This
is documented in the Federal Compliance Gap Analysis (Architecture/Blueprint.md §6.1) and is
acceptable at the commercial baseline. The federal upgrade path requires migration to an HSM."]

---

## 10. Recommendations

| Priority | Recommendation | Target Completion | Owner |
|---------|---------------|------------------|-------|
| 1 | [FILL IN — top priority remediation action from findings] | [FILL IN] | [FILL IN] |
| 2 | [FILL IN] | [FILL IN] | [FILL IN] |
| 3 | Migrate CA private keys to FIPS 140-3 Level 3 HSM | Federal upgrade path | [FILL IN] |

---

## 11. Assessment Team

| Role | Name | Organization |
|------|------|-------------|
| Lead Assessor | Glenn Byron | [FILL IN] |
| Technical Reviewer | [FILL IN] | [FILL IN] |
| System Owner Representative | [FILL IN] | [FILL IN] |

---

## 12. Document Control

| Version | Date | Author | Change Summary |
|---------|------|--------|----------------|
| 0.1 | [FILL IN] | Glenn Byron | Initial template created |
| 1.0 | [FILL IN] | Glenn Byron | Completed with Phase 4 assessment results |

---

*Related documents: `Architecture/SSP-Template.md` (system description and controls),
`Architecture/POAM-Template.md` (open finding tracking), `Compliance-Reports/` (raw scan artifacts).*
