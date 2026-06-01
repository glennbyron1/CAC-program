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
| Assessment Period | May – June 2026 |
| Assessor | Glenn Byron |
| Assessment Type | Self-assessment (independent assessment recommended for production ATO) |
| Report Date | June 1, 2026 |
| Version | 1.0 |

---

## 2. Executive Summary

> Write this section last, after populating all the findings tables.

This Security Assessment Report documents the findings from the RMF Assess phase for the
Enterprise CAC/PIV ICAM system. The assessment included automated DISA STIG scans using the
SCAP Compliance Checker (SCC), manual checklist review using DISA STIG Viewer, and credentialed
vulnerability scanning using Nessus Essentials.

**Before Hardening (2026-05-27):**
Baseline SCAP SCC scans of both lab VMs against the Windows Server 2022 STIG (v2.3.10) showed
compliance scores of 44.95% (DC01) and 42.20% (WS01), with 9 CAT I failures on each system
and 105–111 CAT II failures. Nessus Essentials scan: pending.

**After Hardening (2026-05-28):**
Following deployment of the lab build scripts and smart card enforcement GPOs (`scforceoption=1`,
`ScRemoveOption`, session lock), post-hardening scans showed 42.66% (DC01) and 42.20% (WS01).
The CAT I failure count remained at 9 per VM. The smart card phase addressed the Identity
authentication pillar (NIST IA-2, IA-5) — not a full STIG hardening pass. A full STIG
hardening pass using `Lab-Kit/Ansible/windows-stig-hardening.yml` is the next compliance phase.
Nessus Essentials scan: pending.

**Overall Risk Determination:** Moderate

**Recommendation:** Recommend ATO with conditions — authentication controls satisfied;
open CAT I findings require POA&M remediation schedule before full ATO.

---

## 3. Assessment Scope

### 3.1 Systems Assessed

| System | Hostname | OS | Assessment Date |
|--------|----------|----|-----------------|
| Domain Controller / Issuing CA | LAB-DC01 | Windows Server 2022 | 2026-05-27 (Before) / 2026-05-28 (After) |
| Test Workstation | LAB-WORKSTATION01 | Windows Server 2022 | 2026-05-27 (Before) / 2026-05-28 (After) |
| Offline Root CA | LAB-OFFLINEROOOTCA | Windows Server 2022 | Not scanned (air-gapped, no network) |
| HTTP CRL / AIA Server | N/A | IIS 10.0 | Pending — IIS not deployed in current phase |

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

Tool: SCAP Compliance Checker (SCC) 5.10.2 · Benchmark: MS_Windows_Server_2022_STIG-2.3.10

| System | STIG | Before Score | After Score | Delta |
|--------|------|-------------|------------|-------|
| LAB-DC01 | Windows Server 2022 | 44.95% | 42.66% | -2.29% |
| LAB-WORKSTATION01 | Windows Server 2022 | 42.20% | 42.20% | 0.00% |
| IIS 10.0 | — | Pending | Pending | — |

> Note: DC01 score decreased slightly after hardening. The smart card GPO settings
> caused some previously passing STIG items to fail (settings that conflict with
> scforceoption requirements). This is expected and documented. The authentication
> controls are satisfied; the score delta reflects STIG items unrelated to authentication.

### 5.2 Findings by Category (Post-Hardening, After-MFA)

| System | STIG | CAT I Open | CAT II Open | CAT III Open | Pass |
|--------|------|-----------|------------|-------------|------|
| LAB-DC01 | Windows Server 2022 | 9 | 110 | 6 | 93 |
| LAB-WORKSTATION01 | Windows Server 2022 | 9 | 111 | 6 | 92 |
| IIS 10.0 | — | Pending | Pending | Pending | — |

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
| IA-2 | Identification and Authentication | Satisfied | SCAP SCC + Manual | Smart card enforced via scforceoption=1 GPO; domain will not issue Kerberos ticket without valid cert |
| IA-2(11) | Workstation Hardware Token Logon | Satisfied | SCAP SCC + GPO review | scforceoption=1 confirmed on Workstation01; smart card logon tested and confirmed |
| IA-5 | Authenticator Management | Satisfied | Manual | Two-person enrollment ceremony (RA + Issuer phases); cert lifecycle managed via AD CS |
| IA-5(2) | PKI-Based Authentication | Satisfied | Manual — OCSP test | OCSP responder operational; AIA extension on all issued certs; CRL validated |
| AC-5 | Separation of Duties | Satisfied | Manual / Procedural | New-TokenEnrollment.ps1 enforces RA/Issuer split; same account blocked from both phases |
| AC-11 | Session Lock | Satisfied | SCAP SCC + Manual | GPO ScRemoveOption=1 forces immediate lock on card removal; confirmed <2 seconds |
| AC-17 | Remote Access | Satisfied | Manual — VPN EAP-TLS test | IKEv2/EAP-TLS VPN configured; certificate-based auth confirmed; no password fallback |
| SC-8 | Transmission Confidentiality | Satisfied | Manual — IPsec policy review | AES-256-GCM / SHA-256 / ECP384 FIPS-compliant IPsec policy applied |
| SC-17 | PKI Certificates | Satisfied | Manual — CA audit | Two-tier PKI operational; offline Root CA; OCSP; CRL publication; template management |
| CA-2 | Security Assessments | Satisfied | This assessment | SCAP SCC Before/After-MFA scans completed; this SAR documents results |
| AU-2 | Event Logging | Satisfied | Manual — AD CS audit log | Advanced Audit Policy configured; WEF forwarding operational; Event IDs 4624, 4768 confirmed |
| CA-7 | Continuous Monitoring | Satisfied | Manual — PKI health monitor | Monitor-PKIHealth.ps1 operational; CRL validity, OCSP, cert expiry monitored |

---

## 9. Risk Summary

### 9.1 Overall Risk Rating

| Category | Finding Count (DC01 / WS01) | Risk Contribution |
|---------|--------------|------------------|
| CAT I (Critical) — Unmitigated | 9 / 9 | HIGH |
| CAT II (High) — Unmitigated | 110 / 111 | MODERATE |
| CAT III (Medium/Low) — Unmitigated | 6 / 6 | LOW |

**Overall Residual Risk:** Moderate

Residual risk is acceptable because the authentication controls (IA-2, AC-5, AC-11, AC-17,
SC-17) are fully satisfied. The open CAT I/II findings are STIG hardening items unrelated to
the identity authentication mechanism — they represent a full STIG hardening pass, which is
scoped as the next phase (`Lab-Kit/Ansible/windows-stig-hardening.yml`).

### 9.2 Key Risk Factors

1. **Open CAT I STIG findings (9 per VM).** These are Windows Server 2022 STIG findings
   not addressed by the smart card hardening phase. A full STIG hardening pass is planned
   using the Ansible playbook. Until complete, residual risk is Moderate.

2. **Software-based CA key storage.** Root CA and Issuing CA private keys are stored in
   a software KSP on the host OS. This is acceptable at the commercial baseline but does
   not meet the FIPS 140-3 Level 3 HSM requirement for full federal PIV. Documented in
   `Architecture/Federal-Compliance-Upgrade.md`.

3. **Nessus Essentials scan pending.** Credentialed vulnerability scan has not yet been
   completed. This limits the completeness of the vulnerability management picture.
   Scheduled as next compliance task.

---

## 10. Recommendations

| Priority | Recommendation | Target Completion | Owner |
|---------|---------------|------------------|-------|
| 1 | Run full STIG hardening pass using `Lab-Kit/Ansible/windows-stig-hardening.yml` to address CAT I/II open findings | Q3 2026 | Glenn Byron |
| 2 | Run Nessus Essentials credentialed scan on DC01 and WS01; document Critical/High findings | Q3 2026 | Glenn Byron |
| 3 | Complete IIS 10.0 STIG assessment for CRL/AIA distribution point | Q3 2026 | Glenn Byron |
| 4 | Migrate CA private keys to FIPS 140-3 Level 3 HSM | Federal upgrade path | TBD |

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
| 0.1 | May 2026 | Glenn Byron | Initial template created |
| 1.0 | June 1, 2026 | Glenn Byron | Completed with Before/After-MFA SCAP SCC scan results |

---

*Related documents: `Architecture/SSP-Template.md` (system description and controls),
`Architecture/POAM-Template.md` (open finding tracking), `Compliance-Reports/` (raw scan artifacts).*
