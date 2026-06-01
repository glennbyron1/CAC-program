# CAC Program — Outstanding Tasks

**Author:** Glenn Byron
**Last Updated:** June 1, 2026

Living task list for the CAC/PIV ICAM portfolio project.
✅ Complete · ⬜ Needs hands-on work · 📋 Blocked on After-MFA scan data

---

## Immediate — Do These Now

- ⬜ **Add GitHub repo topics** — log in as glennbyron1, go to the repo page, click the gear icon next to "About", and add:
  ```
  identity-management  pki  smart-card  fido2  active-directory
  certificate-authority  nist-800-53  fips-201  zero-trust  icam
  ad-cs  powershell  disa-stig  hyper-v  rmf  cac
  ```
- ⬜ **Tag v1.0 release** — run in PowerShell, then publish via GitHub → Releases:
  ```powershell
  git tag v1.0 -m "Before-MFA baseline: two-tier PKI, smart card enrollment, SCAP compliance evidence"
  git push origin v1.0
  ```

---

## One-Time Setup

- ✅ `.scrub-patterns.local.json` created with real identifiers (including password)
- ✅ `.idea/` removed from git tracking
- ✅ GitHub email privacy enabled (both options)
- ✅ PowerShell push credentials fixed (Credential Manager + PAT)
- ✅ Git history rewritten — Gmail removed from all commits, noreply address on all 20 commits
- ✅ Scrub-Repo.ps1 run and repo verified clean before all pushes

---

## DevSecOps — Pipeline and IaC

### CI/CD Security Pipeline (GitHub Actions)
- ✅ Secret & sensitive file scan
- ✅ PowerShell lint (PSScriptAnalyzer)
- ✅ CodeQL SAST
- ✅ Trivy container scan
- ✅ Dependency review
- ⬜ Add SBOM generation (Syft or `trivy sbom`) on container build — EO 14028 compliance
- ⬜ Add Gitleaks workflow for deeper secret detection

### Container
- ✅ `docker/scap-summary/` — containerized SCAP XCCDF parser
- ⬜ Push image to GitHub Container Registry (ghcr.io) on merge to main
- ⬜ Add Docker content trust / image signing (cosign)

### Infrastructure as Code (Ansible)
- ✅ `Lab-Kit/Ansible/windows-stig-hardening.yml` — automates 8 STIG sections
- ⬜ Add Ansible playbook for AD health check
- ⬜ Add Ansible playbook for certificate expiry reporting

### Certifications / Learning
- ⬜ CySA+ CS0-003 — lab is being built alongside study (see CySA+ section below)
- ⬜ AZ-500 (Azure Security Engineer) — high DoD value, pairs with Phase 9
- ⬜ WGU MSSWEDOE — enroll after starting new job

---

## Physical Home Lab (Dell 3080 Micro Build)

See `Home_Lab_Build_Guide.md` (personal reference, not in repo).

- ⬜ Confirm RAM in Micro #1 (Hyper-V host) — 32GB min, 64GB ideal
- ⬜ Micro #2 → install OPNsense (Phase 9B VPN appliance)
- ⬜ Rack the two micros in the Tecmojo 6U 10-inch rack
- ⬜ Wire OPNsense between Verizon 5G gateway and the lab switch
- ⬜ Confirm MacBook and main desktop are NOT domain-joined
- ⬜ Upgrade to a compact managed switch when VLANs are needed

---

## Lab Execution — After-MFA Scans (Priority 1)

Before-MFA scans are complete and staged. After-MFA scans are the single most important remaining lab task. Requires the lab VMs to be running.

- ✅ Before-MFA SCAP scan — DC01: **44.95%** (CAT I fail: 9, CAT II: 105, CAT III: 6)
- ✅ Before-MFA SCAP scan — WS01: **42.20%** (CAT I fail: 9, CAT II: 111, CAT III: 6)
- ✅ Before-MFA results staged in `Compliance-Reports/Before-MFA/`
- ✅ Smart card logon confirmed working (Phase 9 Steps 1–5 complete)
- ⬜ **After-MFA SCAP scan on DC01** — run SCC 5.10.2 with CPE override, transfer via LabTransfer SMB share
- ⬜ **After-MFA SCAP scan on WS01** — run SCC 5.10.2, pull via `Copy-Item -FromSession`
- ⬜ Stage After-MFA results: `Stage-Reports.ps1 -Stage After`
- ⬜ Update `Compliance-Reports/README.md` scoring table with real After-MFA numbers

### Optional Compliance Evidence
- ⬜ Nessus Essentials — credentialed scan Before and After hardening (up to 16 IPs, free)
- ⬜ STIG Viewer — review .ckl files for CAT I open findings, document false positives
- ⬜ PKI health check baseline — run `Monitor-PKIHealth.ps1` now that lab is fully built

---

## RMF Templates (Blocked on After-MFA Data)

All templates written. Need After-MFA scan numbers to fill these in.

- 📋 `Architecture/RMF-Templates/SAR-Template.md` — After-MFA SCAP scores, CAT I/II counts, Nessus findings
- 📋 `Architecture/RMF-Templates/POAM-Template.md` — open findings, remediation owners, target dates
- 📋 `Architecture/RMF-Templates/SSP-Template.md` — final compliance posture, After-MFA reference
- 📋 `Architecture/RMF-Templates/Annual-STIG-Rescan-SOP.md` — 2026 baseline scores
- 📋 `STATUS.md` — update Phase 4 checkboxes to ✅

---

## Portfolio Finalization (After After-MFA Scans)

- 📋 Add real screenshots to `Demo-Walkthrough.md` (smart card prompt, Event 4768, VPN connect, PKI health, SCAP delta)
- 📋 Update Portfolio/ Word docs with final After-MFA scores
- 📋 Lead with the Before/After SCAP score delta in README and portfolio docs
- 📋 Final `Scrub-Repo.ps1 -WhatIf` pass before any push with scan data

---

## Phase 8 — Zero Trust Extension ⬜ Scripts Pending

Design complete — `Architecture/Roadmap/CAC_PIV_Phase8_ZeroTrust_Extension.md`.
Gap analysis — `Architecture/CAC_PIV_Program_ZeroTrust_Gap_Analysis.md`.

### 8.1 — Authorization & Least Privilege *(closes Gap A · AC-2, AC-3, AC-5, AC-6)*
- ⬜ `Set-TieredAdminModel.ps1` — AD admin tiering (Tier 0/1/2)
- ⬜ `Set-LeastPrivilegeGPO.ps1` — User Rights Assignment hardening
- ⬜ `New-RBACModel.ps1` — role groups, role → resource mapping
- ⬜ `Set-AuthenticationPolicySilo.ps1` — Kerberos Authentication Policy Silos
- ⬜ `Deploy-ResourceGateway.ps1` — reverse proxy as working PEP demo

### 8.2 — Device Trust *(closes Gap B · IA-3, CM-6, SC-7)*
- ⬜ `New-DeviceCertTemplate.ps1` — machine cert template from Issuing CA
- ⬜ `Enroll-DeviceCertificates.ps1` — device cert autoenrollment
- ⬜ `Set-DeviceComplianceCheck.ps1` — posture gate (AV, patch, BitLocker)
- ⬜ `Update-VPN-DeviceAuth.ps1` — require user + machine certs on VPN

### 8.3 — Continuous & Conditional Access *(closes Gaps C & D · AC-12, IA-2, AU-6)*
- ⬜ `Set-KerberosTicketLifetime.ps1` — shorten TGT/TGS lifetimes
- ⬜ `Deploy-ConditionalAccess.ps1` — PIV federation into Entra ID / AD FS
- ⬜ `New-RiskPolicy.ps1` — step-up auth and deny conditions

### 8.4 — Workload / Non-Person Identity *(optional · Gap E)*
- ⬜ `New-WorkloadCertTemplate.ps1` — short-lived service identity cert template
- ⬜ `Set-ServiceAccountHardening.ps1` — convert to gMSA, remove stored secrets
- ⬜ `Enable-mTLS.ps1` — mutual TLS between two lab services

### 8.5 — Network Segmentation *(closes Gap F · SC-7, AC-4)*
- ⬜ `Set-Microsegmentation.ps1` — default-deny east-west between lab VMs
- ⬜ `Convert-VPNToPerApp.ps1` — per-resource VPN access (ZTNA-style)

### 8.6 — Visibility → Decisioning *(closes Gap G · AU-6, SI-4, IR-4)*
- ⬜ `Deploy-SIEM.ps1` — forward WEF stream into Sentinel or Elastic
- ⬜ `New-DetectionRules.ps1` — anomalous auth, lateral movement detections
- ⬜ `Connect-Analytics-To-Policy.ps1` — risk signal feeds conditional access

### 8.7 — Validation & Evidence
- ⬜ `Invoke-ZeroTrustValidation.ps1` — extend 7-layer validator with ZT checks
- ⬜ Extend `Stage-Reports.ps1` with Before-ZT / After-ZT delta
- ⬜ Update SSP control mapping with Phase 8 control families
- ⬜ `Demo-Walkthrough-ZT.md`

---

## Phase 9 — Cloud Identity & Conditional-Access VPN ⬜ Not Started

Design complete — `Architecture/Roadmap/CAC_PIV_Phase9_Azure_VPN_ConditionalAccess.md`.
Requires: Azure for Students account + free Microsoft 365 Developer tenant.

- ⬜ 9.0 — Cost guardrail + resource group (do this first — never provision without budget alert)
- ⬜ 9.1 — Entra tenant + synthetic test users + MFA enrollment
- ⬜ 9.2 — Azure P2S VPN Gateway authenticated by certs from your Issuing CA
- ⬜ 9.3 — Conditional Access policies (MFA + compliant device)
- ⬜ 9.4 — Device compliance signal (Entra join + Intune)
- ⬜ 9.5 — Sign-in logs + detections
- ⬜ 9.6 — Validation + teardown (`Remove-AzureLabResources.ps1` — run every session)

---

## Phase 9B — On-Prem VPN Appliance ⬜ Not Started

Design complete — `Architecture/Roadmap/CAC_PIV_Phase9B_OnPrem_VPN_Appliance.md`.
Requires: Dell 3080 Micro #2 set up with OPNsense.

- ⬜ 9B.1 — Hardware + network prep, document the appliance
- ⬜ 9B.2 — OPNsense base install + baseline hardening
- ⬜ 9B.3 — PKI integration — issue server + client certs from your Issuing CA
- ⬜ 9B.4 — VPN profile, client install, cert-auth test + negative (revoked cert) test
- ⬜ 9B.5 — Syslog forwarding to CySA+ Splunk lab
- ⬜ 9B.6 — Validation + evidence

---

## CySA+ SOC Analyst Lab ⬜ Not Started (Separate Repo)

Design complete — `CySA_SOC_Analyst_Lab.md` (held locally, not in this repo).
Will get its own GitHub repo. Runs on Hyper-V to reuse existing host.

- ⬜ Create new GitHub repo: `cysa-soc-lab`
- ⬜ Phase 1 — Foundation + architecture Blueprint.md
- ⬜ Phase 2 — Core automation (VMs, Splunk, Sysmon, Nessus, forwarders)
- ⬜ Phase 3 — Log collection + normalization
- ⬜ Phase 4 — Detection + threat hunting (Splunk searches, dashboards)
- ⬜ Phase 5 — Vulnerability management (Nessus credentialed scan)
- ⬜ Phase 5.5 — Optional: Microsoft Sentinel cloud-SIEM (Azure for Students)
- ⬜ Phase 6 — Incident response (Atomic Red Team attacks → detect → document)
- ⬜ Phase 7 — Reporting (incident report, vuln report, MTTD/MTTR dashboard)
- ⬜ Phase 8 — Validation + CySA+ objectives map
- ⬜ Phase 9 — Release prep (README, LICENSE, CI, CHANGELOG)

---

## Phase Summary

| Phase | Status |
|-------|--------|
| 1 — Foundation & Architecture | ✅ Complete |
| 2 — Core Automation Scripts | ✅ Complete |
| 3 — Compliance & Regulatory Docs | ✅ Complete |
| 4 — Lab Execution (Before-MFA) | ✅ Scans done · ⬜ After-MFA pending |
| 5 — RMF Authorize | ✅ Templates done · 📋 data pending |
| 6 — Advanced Automation | ✅ Complete |
| 7 — Portfolio Finalization | 📋 After After-MFA scans |
| 8 — Zero Trust Extension | ⬜ Design done · scripts pending |
| 9 — Azure Cloud VPN + Conditional Access | ⬜ Design done · not started |
| 9B — On-Prem VPN Appliance | ⬜ Design done · hardware needed |
| CySA+ SOC Lab | ⬜ Design done · separate repo |

---

*Build sequence: `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md`*
*RMF templates: `Architecture/RMF-Templates/`*
*Phase 8–9B design: `Architecture/Roadmap/`*
*Zero Trust reference: `Architecture/Zero-Trust-Reference/`*
