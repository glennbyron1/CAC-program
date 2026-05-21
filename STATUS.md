# Program Status — Current Phase Tracker

**Author:** Glenn Byron
**Last Updated:** May 2026

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
| 5 | RMF Authorize — ATO Package | Authorize | 📋 Planned | — |
| 6 | Advanced Automation + Monitoring | Monitor | 📋 Planned | — |
| 7 | Portfolio Finalization | — | 📋 Planned | — |
| 8 | Federal Upgrade Path | Full FISMA/FedRAMP | 🔭 Future | — |

---

## Next Phase Preview

**Phase 5 — RMF Authorize**
Once Phase 4 assessment artifacts are complete, Phase 5 produces the ATO package:
System Security Plan (SSP), finalized POA&M, Security Assessment Report (SAR),
and STIG deviation rationale documentation.

---

*See `ROADMAP.md` for full phase detail. See `Architecture/FedGov-Tools-Setup-Guide.md` for tool procedures.*
