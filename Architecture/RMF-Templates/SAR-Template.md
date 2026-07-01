# Security Assessment Report (SAR)

Document ID: ARCH-ICAM-008
Author: Glenn Byron
Framework: NIST SP 800-53 Rev. 5 CA-2 | NIST SP 800-37 Rev. 2 | DISA RMF Assess Phase

> **How to use this template:** This document summarizes the results of Phase 4 STIG and
> vulnerability assessments. Complete it after all SCAP SCC scans, STIG Viewer checklist reviews,
> and Nessus Essentials scans are finished. The SAR feeds directly into the POA&M
> (`POAM-Template.md`) and SSP (`SSP-Template.md`) for the ATO package.

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
authentication pillar (NIST IA-2, IA-5) — not a full STIG hardening pass. **The full STIG
hardening pass shipped in v1.4** via `Lab-Kit/08-Ansible-STIG/` (ansible-lockdown Windows-2022-STIG
role from a WSL2 control node), moving LAB-DC01 from **44.95% → 86.7%** in three severity-tagged
phases. Scan evidence at `Compliance-Reports/After-Ansible/`. Nessus Essentials scan: completed
2026-06-25 — see `Compliance-Reports/Nessus/`.

**Overall Risk Determination:** Moderate

**Recommendation:** Recommend ATO with conditions — authentication controls satisfied;
open CAT I findings require POA&M remediation schedule before full ATO.

---

## 3. Assessment Scope

### 3.1 Systems Assessed

| System | Hostname | OS | Assessment Date |
|--------|----------|----|-----------------|
| Domain Controller / Issuing CA | LAB-DC01 | Windows Server 2022 | 2026-05-27 (Before) / 2026-05-28 (After-MFA) / 2026-06-30 (After-Ansible) |
| Server VM Test Workstation | LAB-WORKSTATION01 | Windows Server 2022 | 2026-05-27 (Before) / 2026-05-28 (After-MFA) |
| **Physical Windows 11 Endpoint** | **WO02** | **Windows 11 Pro** | **2026-06-02 (After-SmartCard, domain-joined)** |
| Offline Root CA | LAB-OFFLINEROOOTCA | Windows Server 2022 | Not scanned (air-gapped, no network) |
| HTTP CRL / AIA Server | LAB-DC01 (IIS 10.0) | Windows Server 2022 | 2026-06-24 (IIS Server STIG + Site STIG) |

### 3.2 STIGs Assessed

| STIG | Version | Target System | Assessment Method | Checklist File |
|------|---------|---------------|------------------|----------------|
| Microsoft Windows Server 2022 STIG | 2.3.10 | LAB-DC01 + LAB-WORKSTATION01 | SCAP SCC + STIG Viewer manual review | `Compliance-Reports/After-MFA/*-Checklist_MS_Windows_Server_2022_STIG-2.3.10.ckl` |
| **Microsoft Windows 11 STIG** | **2.3.9** | **WO02** | **SCAP SCC + STIG Viewer manual review** | **`Compliance-Reports/Laptop/After-SmartCard/2026-06-02_104513/Results/SCAP/Checklists/*.ckl`** |
| **IIS 10.0 Server STIG** | **3.2.9** | **LAB-DC01 (CRL/AIA endpoint)** | **SCAP SCC** | **`Compliance-Reports/IIS-STIG/2026-06-24_123720/.../Checklist_IIS_10-0_Server_STIG-3.2.9.ckl`** |
| **IIS 10.0 Site STIG** | **2.10.10** | **LAB-DC01 (CRL/AIA site)** | **SCAP SCC** | **`Compliance-Reports/IIS-STIG/2026-06-24_124708/.../Checklist_IIS_10-0_Site_STIG-2.10.10.ckl`** |
| Active Directory Domain Services STIG | V3R2 (or current) | LAB-DC01 | STIG Viewer manual review (queued) | Pending Q3 2026 |
| PKI / Certificate Services STIG | V2R1 (or current) | LAB-DC01 | STIG Viewer manual review (queued) | Pending Q3 2026 |

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

| System | STIG | Before-MFA | After-MFA | After-Ansible (v1.4) | Delta |
|--------|------|-----------|-----------|----------------------|-------|
| LAB-DC01 | Windows Server 2022 2.3.10 | 44.95% | 42.66% | **86.70%** | **+41.75 pts** (vs baseline) |
| LAB-WORKSTATION01 | Windows Server 2022 2.3.10 | 42.20% | 42.20% | — (not in v1.4 scope) | 0.00% |
| **WO02** | **Windows 11 STIG 2.3.9** | **—** (no baseline) | **37.00%** (After-SmartCard) | — (not in v1.4 scope) | n/a |
| LAB-DC01 (IIS Server STIG) | IIS 10.0 Server 3.2.9 | — | **53.85%** | — | n/a |
| LAB-DC01 (IIS Site STIG) | IIS 10.0 Site 2.10.10 | — | **54.55%** | — | n/a |

> **Why DC01 dipped slightly After-MFA (42.66% < 44.95%):** the smart card GPO settings caused some previously passing STIG items to fail (settings that conflict with `scforceoption` requirements). Expected and documented; the authentication controls are satisfied. The After-Ansible **86.7%** result represents the v1.4 full STIG hardening pass via `Lab-Kit/08-Ansible-STIG/` — see `Compliance-Reports/After-Ansible/` for scan archives.
>
> **WO02 baseline note:** WO02 was scanned once after domain join + smart-card GPO application. No pre-enrollment baseline exists because the laptop was scanned only after the full configuration was applied. The 37.00% score against the Windows 11 STIG (MAC-1 Classified profile, 258 rules) is consistent with a Win11 endpoint that has received only the smart card GPO — no broader STIG-aligned hardening yet.

### 5.2 Findings by Category (Post-Hardening, After-MFA)

| System | STIG | CAT I Open | CAT II Open | CAT III Open | Pass | Stage |
|--------|------|-----------|------------|-------------|------|-------|
| LAB-DC01 | Windows Server 2022 | 9 | 110 | 6 | 93 | After-MFA (2026-05-28) |
| LAB-DC01 | Windows Server 2022 | **1** | **27** | **1** | **189** | **After-Ansible (v1.4, 2026-06-30)** |
| LAB-WORKSTATION01 | Windows Server 2022 | 9 | 111 | 6 | 92 | After-MFA (2026-05-28) |
| **WO02** | **Windows 11 STIG 2.3.9** | **13** | **122** | **8** | — | **After-SmartCard (2026-06-02)** |
| LAB-DC01 (IIS Server) | IIS 10.0 Server STIG 3.2.9 | 2 | 8 | 0 | — | 2026-06-24 |
| LAB-DC01 (IIS Site) | IIS 10.0 Site STIG 2.10.10 | 0 | 15 | 2 | — | 2026-06-24 |

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
| IA-2(11) | Workstation Hardware Token Logon | Satisfied | SCAP SCC + GPO review + physical-endpoint test | `scforceoption=1` confirmed on the **WO02 physical Windows 11 laptop**; smart-card-required GPO scoped to the Workstations OU; smart card logon tested end-to-end with YubiKey 5 NFC; 2-second lock-on-removal confirmed (`ScRemoveOption=1`). Smart-card-specific STIG rules `WN22-SO-000120` (Interactive logon: Require smart card) and `WN22-CC-000080` (Smart card removal behavior) PASSED on all scanned systems |
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

| Category | Finding Count (DC01 After-Ansible / WS01 / WO02) | Risk Contribution |
|---------|---------|------------------|
| CAT I (Critical) — Unmitigated | **1** / 9 / 13 | HIGH on WS01 + WO02 (Win11) ; **LOW on DC01 post-v1.4 Ansible pass** |
| CAT II (High) — Unmitigated | **27** / 111 / 122 | MODERATE — LAB-DC01 bulk-remediated in v1.4 (down from 110); WS01 + WO02 pending |
| CAT III (Medium/Low) — Unmitigated | 6 / 6 | LOW |

**Overall Residual Risk:** Moderate

Residual risk is acceptable because the authentication controls (IA-2, AC-5, AC-11, AC-17,
SC-17) are fully satisfied. The remaining open findings are STIG hardening items unrelated to
the identity authentication mechanism — the v1.4 Ansible STIG remediation pass
(`Lab-Kit/08-Ansible-STIG/`) closed the bulk of CAT II / CAT III findings on LAB-DC01 (86.7%
post-Ansible), with the residual gap being controls left off by design (`win2022stig_disruption_high:
false`, `win2022stig_complexity_high: false`) plus manual AUDIT controls and a few Server-2025
vs. 2022-benchmark mismatches.

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
| 1 | ~~Run full STIG hardening pass~~ **Completed 2026-06-30 (v1.4)**: ansible-lockdown Windows-2022-STIG role via `Lab-Kit/08-Ansible-STIG/` applied to LAB-DC01 — 44.95% → 86.7% across CAT I/II/III tiers | 2026-06-30 ✅ | Glenn Byron |
| 2 | Run Nessus Essentials credentialed scan on DC01 and WS01; document Critical/High findings | Q3 2026 | Glenn Byron |
| 3 | Complete IIS 10.0 STIG assessment for CRL/AIA distribution point | Q3 2026 | Glenn Byron |
| 4 | Migrate CA private keys to FIPS 140-3 Level 3 HSM | Federal upgrade path | TBD |

---

## 11. Assessment Team

| Role | Name | Organization |
|------|------|-------------|
| Lead Assessor | Glenn Byron | Lab Program Manager / ISSO |
| Authorizing Official (AO) | Glenn Byron | System Owner / Lab Program Manager — Self-Assessed Lab |
| Technical Reviewer | Self-assessed | Lab environment — no independent reviewer |
| System Owner Representative | Glenn Byron | Lab Program Manager |

> **Note:** This is a personal learning and portfolio lab with no production ATO.
> The assessment demonstrates the RMF workflow and documentation discipline,
> not a formal DoD authorization decision.

---

## 12. Document Control

| Version | Date | Author | Change Summary |
|---------|------|--------|----------------|
| 0.1 | May 2026 | Glenn Byron | Initial template created |
| 1.0 | June 1, 2026 | Glenn Byron | Completed with Before/After-MFA SCAP SCC scan results |

---

*Related documents: `SSP-Template.md` (system description and controls),
`POAM-Template.md` (open finding tracking), `Compliance-Reports/` (raw scan artifacts).*

*Note: This is a personal learning and portfolio lab with no production ATO. The "authorization" here demonstrates the RMF workflow and documentation discipline — not a formal DoD authorization decision.*