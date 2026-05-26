# Program Status — Current Phase Tracker

**Author:** Glenn Byron
**Last Updated:** May 23, 2026

---

## ► CURRENT PHASE: 4 — RMF Assess: STIG Execution & Evidence Collection

**RMF Step:** Assess (CA-2, CA-7)
**Phase Start:** May 2026
**Phase Goal:** Execute DISA STIG audits, collect before/after scan evidence, produce STIG Viewer checklists and initial POA&M/SAR artifacts.

---

## Phase 4 Progress Checklist

Update this file as items are completed. Change `[ ]` to `[x]`.

### 4.1 — SCAP SCC Automated Scans
- [ ] Install SCAP SCC from `FedCompliance-Tools\00-SCAP-SCC\`
- [ ] Import SCAP 1.3 benchmarks from `FedCompliance-Tools\03-SCAP-Content\`
- [ ] Run **Before-MFA** baseline scan on clean Windows Server VM
- [ ] Export XCCDF XML + HTML report → stage with `.\Stage-Reports.ps1` (option 1)
- [ ] Apply `Build-CAC-Lab.ps1` + `Build-CA-GPO.ps1` + smart card GPOs
- [ ] Reboot VM; run **After-MFA** hardened scan
- [ ] Export XCCDF XML + HTML report → stage with `.\Stage-Reports.ps1` (option 2)

### 4.2 — STIG Viewer Checklists (.ckl)
- [ ] Install DISA STIG Viewer from `FedCompliance-Tools\01-STIG-Viewer\`
- [ ] Windows Server 2022 STIG — import XCCDF, complete CAT I + CAT II manual review
- [ ] Active Directory Domain Services STIG checklist
- [ ] PKI / AD CS Certificate Services STIG checklist
- [ ] IIS 10.0 STIG (HTTP CRL/AIA distribution server)
- [ ] Export all completed checklists → `Compliance-Reports\After-MFA\`

### 4.3 — Nessus Essentials Vulnerability Scans
- [ ] Activate Nessus Essentials (free key from tenable.com)
- [ ] Configure credentialed scan (domain admin credentials)
- [ ] Before-hardening scan → `Compliance-Reports\Before-MFA\Baseline-Vulnerability.pdf`
- [ ] After-hardening scan → `Compliance-Reports\After-MFA\Hardened-Vulnerability.pdf`
- [ ] Document remediation for all Critical + High findings

### 4.4 — RMF Assessment Artifacts
- [ ] Update `Compliance-Reports\README.md` with real SCAP SCC scores + Nessus counts
- [ ] Draft initial POA&M (open findings, risk ratings, remediation schedule)
- [ ] Draft Security Assessment Report (SAR) summary
- [ ] End-to-end validation: smart card logon, lock-on-removal, VPN EAP-TLS

---

## Phase History

| Phase | Title | RMF Step | Status | Completed |
|-------|-------|----------|--------|-----------|
| 1 | Foundation & Architecture | Prepare + Categorize | ✅ Complete | May 2026 |
| 2 | Core Automation Scripts | Select + Implement | ✅ Complete | May 2026 |
| 3 | Compliance & Regulatory Docs | Select — Tailoring | ✅ Complete | May 2026 |
| **4** | **RMF Assess — STIG Execution** | **Assess** | **🔄 In Progress** | — |
| 5 | RMF Authorize — ATO Package | Authorize | 🔄 In Progress (templates done) | — |
| 6 | Advanced Automation + Monitoring | Monitor | 🔄 In Progress | — |
| 7 | Portfolio Finalization | — | 📋 Planned | — |
| 8 | Federal Upgrade Path | Full FISMA/FedRAMP | 🔭 Future | — |

---

## Next Phase Preview

**Phase 5 — RMF Authorize** 🔄 In Progress
All ATO package templates are drafted:
- `SSP-Template.md` (ARCH-ICAM-006) — system boundary, controls, ATO decision block
- `POAM-Template.md` (ARCH-ICAM-007) — finding tracking, risk acceptance register
- `SAR-Template.md` (ARCH-ICAM-008) — before/after assessment results, risk rating
- `STIG-Deviation-Rationale.md` (ARCH-ICAM-010) — pre-populated with architecture-specific deviations
- `ATO-Letter-Template.md` (ARCH-ICAM-009) — AO authorization memorandum

**Remaining:** Populate SSP/POA&M/SAR with real Phase 4 scan data, then submit to AO.

**Phase 5 — CSET item complete:**
- `CSET-Assessment-Guide.md` (ARCH-ICAM-012) ✅ — CSET installation, question set guidance, CAC/PIV answer mapping, MD SB 871 compliance statement

**Phase 6 — PKI Automation & Continuous Monitoring** ✅ Automation Complete
- `New-TokenEnrollment.ps1` (SCRIPT-ICAM-011) ✅ — two-phase RA/Issuer ceremony with AC-5 enforcement
- `Monitor-PKIHealth.ps1` (SCRIPT-ICAM-012) ✅ — CRL/OCSP health, cert expiry alerts, email notification
- `Set-AuditLogForwarding.ps1` (SCRIPT-ICAM-013) ✅ — WEF Collector/Source modes, audit policy, SIEM XPath
- `New-CertificateTemplates.ps1` (SCRIPT-ICAM-014) ✅ — Smart Card Logon and Admin templates via PSPKI
- `Set-OCSPResponder.ps1` (SCRIPT-ICAM-015) ✅ — Online Responder install, signing cert, AIA update
- `New-YubiKeyToken.ps1` (SCRIPT-ICAM-016) ✅ — YubiKey PIV provisioning: reset, management key, PIN/PUK, key gen, CA enrollment, cert import, audit log
- `Annual-STIG-Rescan-SOP.md` (ARCH-ICAM-011) ✅ — full annual re-assessment cycle and ATO renewal checklist

**Live-Server Tooling** (added May 23, 2026) ✅ Complete
- `Live-Servers/Test-ServerReadiness.ps1` ✅ — pre-deployment role-based readiness checker (DC, IssuingCA, OfflineRootCA, Workstation)
- `Live-Servers/Test-GPOCompliance.ps1` ✅ — GPO existence + application + registry settings validator
- `Live-Servers/Install-Guide.md` ✅ — 6-phase live server deployment walkthrough
- `Live-Servers/GPO-Check-Guide.md` ✅ — how-to guide for the GPO compliance checker

**Lab Infrastructure** (added May 22, 2026) ✅ Complete
- `Lab-Kit/01-HyperV-Host/New-LabVMs.ps1` ✅ — creates lab VMs (OfflineRootCA, DC01, Workstation01) in Hyper-V
- `Lab-Kit/01-HyperV-Host/Set-VMPostConfig.ps1` ✅ — post-OS static IP, WinRM, timezone, role-specific configuration
- `Lab-Kit/01-HyperV-Host/Unattend-Server.xml` ✅ — hands-free Windows Server install (Gen 2, UEFI, EFI partition)
- `Package-LabKit.ps1` ✅ — packages self-contained Lab-Kit + Tools-Kit ZIP for USB transfer

---

*See `ROADMAP.md` for full phase detail. See `Architecture/FedGov-Tools-Setup-Guide.md` for tool procedures.*
