# Project Roadmap — Enterprise CAC/PIV Identity & Access Management Program

**Author:** Glenn Byron
**Last Updated:** May 2026
**Document ID:** ROAD-ICAM-001
**Framework:** NIST RMF SP 800-37 Rev. 2 | DISA STIG | NIST SP 800-53 Rev. 5 | FIPS 201-3
**Status Key:** ✅ Complete | 🔄 In Progress | 📋 Planned | 🔭 Future

> 📍 **Current Phase: 4 — RMF Assess: STIG Execution & Evidence Collection**
> For the active checklist and per-item progress tracking, see [`STATUS.md`](STATUS.md).

---

## NIST RMF Phase Mapping

This program follows the NIST Risk Management Framework (SP 800-37 Rev. 2) lifecycle.
Each project phase maps to one or more RMF steps.

| RMF Step | Description | Program Phase |
|----------|-------------|---------------|
| **Prepare** | Establish risk management roles, system boundary, security strategy | Phase 1 — Foundation & Architecture |
| **Categorize** | Determine system impact level (FIPS 199 / CNSSI 1253) | Phase 1 — Foundation & Architecture |
| **Select** | Choose NIST SP 800-53 controls; tailor baselines; apply DISA STIGs | Phase 2 & 3 — Automation + Docs |
| **Implement** | Deploy controls via automation scripts, GPOs, PKI configuration | Phase 2 — Core Automation Scripts |
| **Assess** | SCAP SCC STIG scans, STIG Viewer checklists, Nessus vulnerability scans | Phase 4 — RMF Assess / STIG Execution |
| **Authorize** | Package findings; produce SAR, POA&M, SSP; obtain ATO | Phase 5 — RMF Authorize |
| **Monitor** | Continuous monitoring plan; delta CRL, OCSP, SIEM forwarding, annual STIG re-scans | Phase 6 — Continuous Monitoring |

---

## DISA STIG Coverage Matrix

STIGs applicable to this program's environment. All must have completed STIG Viewer
checklists (.ckl files) before an Authorization to Operate (ATO) can be granted.

| Technology | STIG Title | Applies To | Status |
|-----------|-----------|-----------|--------|
| Windows Server 2022 | Microsoft Windows Server 2022 STIG | Domain Controller, Issuing CA server | 🔄 In Progress |
| Windows Server 2019 | Microsoft Windows Server 2019 STIG | Offline Root CA host (if applicable) | 📋 Planned |
| Active Directory | Active Directory Domain Services STIG | All AD-joined systems | 📋 Planned |
| PKI / AD CS | PKI and Certificate Services STIG | Root CA, Issuing CA | 📋 Planned |
| IIS 10.0 | Microsoft IIS 10.0 Site STIG | HTTP CRL/AIA distribution server | 📋 Planned |
| Windows Firewall | Windows Firewall with Advanced Security STIG | All Windows endpoints | 📋 Planned |
| MS Defender AV | Microsoft Windows Defender Antivirus STIG | All Windows endpoints | 📋 Planned |
| Windows 11 | Microsoft Windows 11 STIG | Smart card-enrolled workstations | 📋 Planned |

> STIG content downloaded via `Download-FedCompliance-Kit.ps1` → `02-STIG-Content\`
> STIG scanning executed via SCAP SCC using content in `03-SCAP-Content\`
> Completed checklists (.ckl) stored in `Compliance-Reports/` after Phase 4 execution.

---

## Phase 1 — Foundation & Architecture ✅ Complete
**RMF: Prepare + Categorize**

Core PKI design, system boundary definition, and repository infrastructure.

- ✅ System boundary defined: Domain Controller, Offline Root CA, Enterprise Issuing CA, HTTP CRL server, Windows endpoints
- ✅ Impact categorization baseline: Confidentiality HIGH / Integrity HIGH / Availability MODERATE (PKI system)
- ✅ Two-tier PKI topology design (`Architecture/Blueprint.md` — ARCH-ICAM-001)
- ✅ CAPolicy.inf and CRL/AIA endpoint reference templates (`/Templates/`)
- ✅ Repository security pipeline (`.gitignore`, `Scrub-Repo.ps1`, `.scrub-patterns.example.json`)
- ✅ `MIT LICENSE`, `SECURITY.md`, `AUTHORS.md`, `MAINTAINER-SETUP.md`
- ✅ `README.md` — architecture overview, NIST SP 800-53 control mapping, GitHub topic tags

---

## Phase 2 — Core Automation Scripts ✅ Complete
**RMF: Select + Implement**

Production-ready PowerShell tooling that implements selected SP 800-53 controls.

| Script | Controls Implemented |
|--------|---------------------|
| `Build-CAC-Lab.ps1` | IA-2 — Identification and Authentication |
| `Build-CA-GPO.ps1` | AC-11 (lock-on-removal), IA-2(11) (smart card enforcement) |
| `Stage-Reports.ps1` | CA-2 — Security Assessments, AU-2 — Event Logging |
| `Download-OfflineCA-Kit.ps1` | SC-17 — PKI Certificates, SC-28 — Protection at Rest |
| `Download-IssuingCA-Kit.ps1` | SC-17 — PKI Certificates, IA-5 — Authenticator Management |
| `Download-FedCompliance-Kit.ps1` | CA-2 — Security Assessments, CA-7 — Continuous Monitoring |
| `Deploy-VPNClient.ps1` | AC-17 — Remote Access, SC-8 — Transmission Confidentiality, IA-2 — MFA Enforcement |

---

## Phase 3 — Compliance & Regulatory Documentation ✅ Complete
**RMF: Select — Control Tailoring, Baseline Documentation**

Full regulatory traceability and STIG audit workflow documentation.

- ✅ `Regulatory-Alignment.md` — CISA ZTMM v2.0, NIST CSF 2.0, CISA CPGs, MD SB 871 (ARCH-ICAM-003)
- ✅ `STIG-Hardening-Guide.md` — SCAP SCC + ACAS/Nessus full audit cycle SOP
- ✅ `FedGov-Tools-Setup-Guide.md` — setup procedures for SCAP SCC, STIG Viewer, Nessus, CSET, SCT, Policy Analyzer (ARCH-ICAM-004)
- ✅ `Blueprint.md` — physical access convergence model, PACS LAK levels, federal compliance gap analysis
- ✅ `Compliance-Reports/` — before/after directory structure and scoring dashboard README
- ✅ NIST SP 800-53 Rev. 5 control mapping (IA-2, IA-2(11), AC-11, AC-5) documented in README
- ✅ `WatchGuard-IKEv2-VPN-Guide.md` — IKEv2 EAP-TLS VPN configuration guide (Fireware Web UI, AD CS cert templates, EAP-TLS XML, troubleshooting, NIST control mapping AC-17/SC-8/SC-28) (ARCH-ICAM-005)

---

## Phase 4 — RMF Assess: STIG Execution & Evidence Collection 🔄 In Progress
**RMF: Assess — CA-2 Security Assessments, CA-7 Continuous Monitoring**

Execute DISA STIG audits, collect before/after scan evidence, produce STIG checklists
and a Security Assessment Report. This is the core RMF Assess deliverable phase.

### 4.1 SCAP SCC Scanning (Automated STIG Assessment)
- ⬜ Install SCAP SCC from `FedCompliance-Tools\00-SCAP-SCC\` and import SCAP 1.3 benchmarks from `03-SCAP-Content\`
- ⬜ Execute **Before-MFA baseline scan** on clean Windows Server VM (SCAP SCC → XCCDF + HTML)
- ⬜ Stage baseline reports: `.\Stage-Reports.ps1` → option 1 (`Compliance-Reports\Before-MFA\`)
- ⬜ Apply `Build-CAC-Lab.ps1` + `Build-CA-GPO.ps1` + smart card enforcement GPOs
- ⬜ Reboot VM; execute **After-MFA hardened scan** (SCAP SCC → XCCDF + HTML)
- ⬜ Stage hardened reports: `.\Stage-Reports.ps1` → option 2 (`Compliance-Reports\After-MFA\`)

### 4.2 STIG Viewer Checklists (.ckl Artifacts)
- ⬜ Install DISA STIG Viewer from `FedCompliance-Tools\01-STIG-Viewer\`
- ⬜ Import Windows Server 2022 STIG XCCDF → merge SCAP SCC automated results
- ⬜ Complete manual review of CAT I (Critical) findings not covered by SCAP automation
- ⬜ Complete manual review of CAT II (High) findings
- ⬜ Export completed checklist: `Compliance-Reports\After-MFA\WinServer2022-STIG.ckl`
- ⬜ Import and complete Active Directory Domain Services STIG checklist
- ⬜ Import and complete PKI / AD CS STIG checklist (Certificate Services STIG)
- ⬜ Import and complete IIS 10.0 STIG checklist (HTTP CRL server)

### 4.3 Vulnerability Scanning (ACAS / Nessus Essentials)
- ⬜ Activate Nessus Essentials (free key from tenable.com), configure credentialed scan
- ⬜ Execute credentialed baseline scan (pre-hardening) → `Compliance-Reports\Before-MFA\Baseline-Vulnerability.pdf`
- ⬜ Execute credentialed post-hardening scan → `Compliance-Reports\After-MFA\Hardened-Vulnerability.pdf`
- ⬜ Document remediation actions for all Critical and High Nessus findings

### 4.4 RMF Assessment Artifacts
- ⬜ Update `Compliance-Reports\README.md` scoring table with real SCAP SCC scores and Nessus counts
- ⬜ Produce initial **Plan of Action & Milestones (POA&M)** — list open STIG findings with remediation timelines
- ⬜ Produce **Security Assessment Report (SAR)** summary — findings, risk levels, remediation status
- ⬜ End-to-end operational validation: smart card logon, lock-on-removal (2-second trigger), VPN EAP-TLS

---

## Phase 5 — RMF Authorize: Package & ATO Documentation 📋 Planned
**RMF: Authorize — CA-6 Authorization**

Produce the documentation package required to support an Authorization to Operate.

- ⬜ **System Security Plan (SSP)** — document all implemented SP 800-53 controls, system boundary, data flows, and inherited controls
- ⬜ **POA&M** finalized — all open STIG findings tracked with risk acceptance or remediation schedule
- ⬜ **SAR** finalized — comprehensive assessment findings with risk ratings (Critical/High/Medium/Low)
- ⬜ STIG deviation rationale documented for any findings accepted as operational requirements
- ⬜ Authorizing Official (AO) package outline — boundary diagram, control inheritance diagram, ATO letter template
- ⬜ CSET assessment export — OT maturity level documentation (MD SB 871 §9-2705(b)(3))

---

## Phase 6 — Advanced PKI Automation & Continuous Monitoring 📋 Planned
**RMF: Monitor — CA-7 Continuous Monitoring, SI-4 System Monitoring**

Automate remaining token lifecycle gaps and establish ongoing monitoring posture.

### PKI Automation
- ⬜ Certificate template automation — Smart Card Logon and Admin templates via PowerShell
- ⬜ `New-TokenEnrollment.ps1` — guided RA/Issuer separation-of-duties enrollment workflow (AC-5)
- ⬜ YubiKey provisioning script — `ykman` integration, PIN enforcement, slot management
- ⬜ OCSP responder configuration automation
- ⬜ CRL expiry monitoring — alert before 6-month Root CA CRL expires

### Continuous Monitoring (RMF Monitor Phase)
- ⬜ AD CS audit log forwarding to SIEM (certutil -setreg CA\AuditFilter 127 already applied)
- ⬜ Automated delta STIG scan schedule — monthly SCAP SCC re-scan with variance reporting
- ⬜ Windows Event Log forwarding configuration for smart card logon events (Event IDs 4768, 4769, 4776)
- ⬜ CRL / OCSP health monitoring script — verify revocation endpoints are reachable and current
- ⬜ Annual STIG re-scan procedure documented (CM-6, CA-7 compliance)

---

## Phase 7 — Portfolio Finalization 📋 Planned

- ⬜ All `Compliance-Reports/` scoring tables populated with real lab scan results
- ⬜ All STIG checklist (.ckl) files committed to `Compliance-Reports/After-MFA/`
- ⬜ Demo walkthrough — screenshots or video embedded in README showing smart card logon end-to-end
- ⬜ Final `Scrub-Repo.ps1 -WhatIf` sanitization review → push to public GitHub
- ⬜ GitHub topic tags applied per README recommendations

---

## Phase 8 — Federal Upgrade Path 🔭 Future
**RMF: Full FISMA / FedRAMP Authorization Tier**

Architectural changes required to elevate from commercial enterprise baseline to a
federally authorized system. See `Architecture/Blueprint.md §6` for detailed gap analysis.

- ⬜ HSM integration — migrate CA private keys to FIPS 140-3 Level 3 Hardware Security Module (SC-17)
- ⬜ FBCA cross-certification — chain internal Issuing CA to the Federal Common Policy CA (NIST SP 800-217)
- ⬜ GSA APL procurement — FIPS 201-3 approved token, reader, and middleware list (IA-3)
- ⬜ SP 800-157 derived credential automation — PIV card as cryptographic voucher for secondary token issuance
- ⬜ DISA STIG re-assessment under federal baseline (High system categorization, all CAT I findings remediated)
- ⬜ FedRAMP / FISMA full ATO package — system security plan, continuous monitoring strategy, incident response plan

---

## Immediate Next Action — Phase 4 Kickoff

All architecture, automation, and documentation is complete (RMF Prepare through Select/Implement).
The next milestone is the RMF **Assess** phase: executing DISA STIG audits and populating evidence.

```powershell
# Step 1 — Download all federal compliance tools (SCAP SCC, STIG Viewer, Nessus, etc.)
.\Automation-Scripts\Download-FedCompliance-Kit.ps1

# Step 2 — Install SCAP SCC, import SCAP 1.3 benchmarks from FedCompliance-Tools\03-SCAP-Content\
# (See Architecture\FedGov-Tools-Setup-Guide.md §1 for step-by-step)

# Step 3 — Run pre-hardening SCAP SCC scan on clean VM, then stage:
.\Stage-Reports.ps1    # option 1 — Before-MFA

# Step 4 — Apply hardening scripts
.\Automation-Scripts\Build-CAC-Lab.ps1
.\Automation-Scripts\Build-CA-GPO.ps1

# Step 5 — Reboot, re-scan, stage post-hardening results:
.\Stage-Reports.ps1    # option 2 — After-MFA

# Step 6 — Open STIG Viewer, import XCCDF results, complete .ckl checklists
# (See Architecture\FedGov-Tools-Setup-Guide.md §2)
```

---

## Reference Documents

| Document | Location | RMF Role |
|----------|----------|----------|
| System Architecture Blueprint | `Architecture/Blueprint.md` | Prepare / Categorize |
| Regulatory Alignment Mapping | `Architecture/Regulatory-Alignment.md` | Select / control tailoring |
| STIG Hardening Guide | `Architecture/STIG-Hardening-Guide.md` | Assess — SCAP SCC workflow |
| FedGov Tools Setup Guide | `Architecture/FedGov-Tools-Setup-Guide.md` | Assess — all tool procedures |
| WatchGuard IKEv2 VPN Guide | `Architecture/WatchGuard-IKEv2-VPN-Guide.md` | Implement — remote access controls (AC-17, SC-8) |
| Before/After Compliance Reports | `Compliance-Reports/` | Assess — evidence artifacts |
| STIG Checklists (.ckl) | `Compliance-Reports/After-MFA/` | Assess — manual findings |
| POA&M | *(Phase 5 deliverable)* | Authorize |
| System Security Plan (SSP) | *(Phase 5 deliverable)* | Authorize |
| Security Assessment Report (SAR) | *(Phase 5 deliverable)* | Authorize |
| Continuous Monitoring Plan | *(Phase 6 deliverable)* | Monitor |
