# 🗺️ Repository Map & Navigation Guide

Welcome. This repository contains over six weeks of hands-on engineering, automated infrastructure-as-code, and federal compliance documentation. Use this guide to navigate the system based on your specific goals.

---

## ⚡ What This Repo Is (in 20 seconds)

A fully automated Active Directory + PKI lab that implements:

- **Smart card (CAC/PIV) authentication** via hardware tokens.
- **Certificate-based VPN** tunnels across Azure and on-prem assets.
- **SCAP/STIG compliance** automation and remediation workflows.
- **RMF documentation** packages including a full SSP, POA&M, and SAR.

| | |
| :--- | :--- |
| ✅ **Real-World System:** | Modeled directly after a DoD-style ICAM / Zero Trust architecture. |
| ✅ **Tangible Evidence:** | Backed by live automation scripts, raw scan results, and visual artifacts. |

---

## ⚡ Quick Proof (2–3 minutes)

If you only have a few minutes to evaluate this project, follow this rapid review path:

1. **Open** [`Screenshots/05-vpn-azure-eap-cert-auth-no-password.png`](Screenshots/05-vpn-azure-eap-cert-auth-no-password.png) to verify passwordless VPN authentication using the hardware certificate.
2. **Check** [`Compliance-Reports/After-Ansible/`](Compliance-Reports/After-Ansible/) for the raw SCC scan archives (2 zip files) that document the climb from **44.95% → 86.7%**, plus [`Compliance-Reports/README.md`](Compliance-Reports/README.md) for the scoring table with per-CAT closures.
3. **Read** [`Portfolio/CAC-Program-Plain-English-Overview.docx`](Portfolio/CAC-Program-Plain-English-Overview.docx) for a high-level, 2-page executive summary.

*This immediately demonstrates the functional engineering value and compliance validity of the system.*

---

## 📊 Project Status & Maturity

| Component | Status | Notes |
| :--- | :--- | :--- |
| **Domain Controller (`LAB-DC01`)** | ✅ Hardened | SCAP STIG score raised to **86.7%** via Ansible. |
| **Workstation (`WO02`)** | ⚠️ Baseline only | Baseline captured (37.00% SCAP, Win 11 STIG 2.3.9). Not on the roadmap for automated hardening — WO02 is a physical endpoint where the demo value is the smart-card enforcement itself, not the broader STIG score. Honest scope decision. |
| **Smart Card Authentication** | ✅ Working | YubiKey deployment + Kerberos PKINIT validated. |
| **Azure P2S VPN** | ✅ Working | End-to-end EAP-TLS cryptographic tunnel operational. |
| **Zero Trust Phase 8** | 🔧 In Progress | 21 scripts written and syntax-validated — not yet run against a live host. |

---

## 🗺️ Architecture Overview

The complete cryptographic trust flow moves from the air-gapped **Offline Root CA ➔ Enterprise Issuing CA ➔ User Smart Card Certificate ➔ Kerberos Ticket Verification**.

For full network diagrams, switch layouts, and trust chain visualizations, see:

👉 [`Architecture/Lab-Topology.md`](Architecture/Lab-Topology.md)

---

## 🎯 Pick the Path That Matches Your Role

Different readers come here for different reasons — pick the path below that fits what you actually need.

### 💼 Hiring Manager / Recruiter

*Goal: evaluate skills and see proof of work, fast.*

1. [`Portfolio/CAC-Program-Plain-English-Overview.docx`](Portfolio/CAC-Program-Plain-English-Overview.docx) — non-technical 2-page summary.
2. [`Screenshots/`](Screenshots/) — visual evidence of the 8 core lab milestones (PIN prompts, VPN states, etc.).
3. [`Project-Narrative.md`](Project-Narrative.md) — Q&A format covering design decisions and the hardest bugs solved.

### 🛠️ Engineer

*Goal: deploy, review, or extend the actual automation.*

1. [`Lab-Kit/START-HERE.md`](Lab-Kit/START-HERE.md) and [`Lab-Kit/LAB-DAY-CHECKLIST.md`](Lab-Kit/LAB-DAY-CHECKLIST.md) — prerequisites and setup order.
2. [`Lab-Kit/03-DomainController/`](Lab-Kit/03-DomainController/) — core Active Directory & PKI code.
3. [`Lab-Kit/08-Ansible-STIG/`](Lab-Kit/08-Ansible-STIG/) — the automation that raised the SCAP score to 86.7%. *(Note: Zero Trust Phase 8 scripts are written but not yet executed — see Project Status above.)*

### 📋 ISSO / Compliance Officer

*Goal: assess regulatory alignment, control mapping, and audit evidence.*

1. [`Architecture/RMF-Templates/SSP-Template.md`](Architecture/RMF-Templates/SSP-Template.md) — NIST control mapping / System Security Plan.
2. [`Architecture/RMF-Templates/POAM-Template.md`](Architecture/RMF-Templates/POAM-Template.md) — vulnerability tracking and remediation plan (POA&M).
3. [`Architecture/RMF-Templates/SAR-Template.md`](Architecture/RMF-Templates/SAR-Template.md) — Security Assessment Report.
4. [`Compliance-Reports/`](Compliance-Reports/) — raw SCC and Ansible scan outputs, including before/after evidence.

### 📚 Deep Dive Auditor / Reviewer

*Goal: read the full story, not just the artifacts.*

1. [`LAB-LEARNING-GUIDE.md`](LAB-LEARNING-GUIDE.md) — what was learned and why, phase by phase.
2. [`Project-Narrative.md`](Project-Narrative.md) — Q&A on design choices and the hardest problems solved.
3. [`WALKTHROUGH.md`](WALKTHROUGH.md) — a full guided tour of the build, start to finish.

---

## 🛠️ Repository Blueprint (By Lifecycle Phase)

The `Lab-Kit/` folder is sequenced chronologically by deployment order. Follow this order if building the lab from scratch:

1. **Phase 1:** [`Lab-Kit/01-HyperV-Host/`](Lab-Kit/01-HyperV-Host/) — Virtualization layer setup.
2. **Phase 2:** [`Lab-Kit/02-OfflineRootCA/`](Lab-Kit/02-OfflineRootCA/) — Air-gapped certificate ceremony.
3. **Phase 3:** [`Lab-Kit/03-DomainController/`](Lab-Kit/03-DomainController/) — Active Directory, Issuing CA, and token enrollment.
4. **Phase 4:** [`Lab-Kit/04-Workstation/`](Lab-Kit/04-Workstation/) — Client configuration and VPN tunnels.
5. **Phase 5:** [`Lab-Kit/05-Compliance/`](Lab-Kit/05-Compliance/) — Automated SCAP compliance scanning.
6. **Phase 6:** [`Lab-Kit/06-PhysicalEndpoint/`](Lab-Kit/06-PhysicalEndpoint/) — Onboarding physical laptops via vTPM.
7. **Phase 7:** [`Lab-Kit/07-ZeroTrust/`](Lab-Kit/07-ZeroTrust/) — Advanced security scaffolding (Silos, microsegmentation).
8. **Phase 8:** [`Lab-Kit/08-Ansible-STIG/`](Lab-Kit/08-Ansible-STIG/) — Automated STIG remediation.

---

## 🔍 Where to Find Specific Deliverables

| If you are looking for... | ...Go to this file or folder |
| :--- | :--- |
| **YubiKey Runbooks** | [`Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md`](Lab-Kit/Reference/RUNBOOK-YubiKey-Enrollment.md) |
| **Bugs & Lessons Learned** | [`Architecture/Lessons-Learned/`](Architecture/Lessons-Learned/) — indexed by severity in [`README.md`](Architecture/Lessons-Learned/README.md). Headlined by the **Silent TPM VSC Fallback discovery** (silent hardware-factor demotion, HIGH severity, NIST IA-2(11) mapping). |
| **Network Topology Diagrams** | [`Architecture/Lab-Topology.md`](Architecture/Lab-Topology.md) |
| **Azure P2S VPN Design** | [`Architecture/Azure-VPN-Guide.md`](Architecture/Azure-VPN-Guide.md) |
| **Troubleshooting & Lockouts** | [`Lab-Kit/Reference/TROUBLESHOOTING.md`](Lab-Kit/Reference/TROUBLESHOOTING.md) |
| **Ansible STIG Automation** | [`Lab-Kit/08-Ansible-STIG/`](Lab-Kit/08-Ansible-STIG/) |
| **NIST Control Mapping (SSP)** | [`Architecture/RMF-Templates/SSP-Template.md`](Architecture/RMF-Templates/SSP-Template.md) |
| **Vulnerability Tracking (POA&M)** | [`Architecture/RMF-Templates/POAM-Template.md`](Architecture/RMF-Templates/POAM-Template.md) |
| **Security Assessment Report (SAR)** | [`Architecture/RMF-Templates/SAR-Template.md`](Architecture/RMF-Templates/SAR-Template.md) |
| **Raw Compliance Scan Evidence** | [`Compliance-Reports/`](Compliance-Reports/) (including [`After-Ansible/`](Compliance-Reports/After-Ansible/) for the v1.4 hardening pass) |
| **Latest release notes** | [`v1.4` on GitHub Releases](https://github.com/glennbyron1/CAC-program/releases/tag/v1.4) |
