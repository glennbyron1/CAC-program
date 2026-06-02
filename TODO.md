# CAC Program — Outstanding Tasks

**Author:** Glenn Byron
**Last Updated:** June 1, 2026 (evening)

Living task list for the CAC/PIV ICAM portfolio project.
✅ Complete · ⬜ Needs hands-on work

---

## Immediate — Do These Now

- ⬜ **Add GitHub repo topics** — log in as glennbyron1, repo page → gear icon next to "About":
  ```
  identity-management  pki  smart-card  fido2  active-directory
  certificate-authority  nist-800-53  fips-201  zero-trust  icam
  ad-cs  powershell  disa-stig  hyper-v  rmf  cac
  ```
- ⬜ **Tag v1.0 release** — PowerShell, then publish via GitHub → Releases:
  ```powershell
  git tag v1.0 -m "Before-MFA baseline: two-tier PKI, smart card enrollment, SCAP compliance evidence"
  git push origin v1.0
  ```

---

## One-Time Setup ✅ Complete

- ✅ `.scrub-patterns.local.json` created with real identifiers
- ✅ GitHub email privacy enabled
- ✅ PowerShell push credentials fixed
- ✅ Git history rewritten — Gmail removed from all commits
- ✅ Repo verified clean — Scrub-Repo.ps1 run before all pushes

---

## CI/CD & Automation ✅ Complete

### GitHub Actions
- ✅ Secret & sensitive file scan
- ✅ PowerShell lint (PSScriptAnalyzer)
- ✅ CodeQL SAST
- ✅ Dependency review
- ✅ Gitleaks — full git history secret scan (weekly + every push)

### Ansible Playbooks
- ✅ `Lab-Kit/Ansible/windows-stig-hardening.yml` — STIG remediation (8 sections)
- ✅ `Lab-Kit/Ansible/ad-health-check.yml` — stale accounts, privileged groups, smart card enforcement, scforceoption guard
- ✅ `Lab-Kit/Ansible/cert-expiry-report.yml` — Root CA, Issuing CA, user certs, OCSP, CRL expiry

---

## Lab Execution — SCAP Scans ✅ Complete

- ✅ Before-MFA SCAP scan — DC01: **44.95%** (CAT I fail: 9, CAT II: 105, CAT III: 6)
- ✅ Before-MFA SCAP scan — WS01: **42.20%** (CAT I fail: 9, CAT II: 111, CAT III: 6)
- ✅ Before-MFA results staged in `Compliance-Reports/Before-MFA/`
- ✅ Smart card logon confirmed working
- ✅ After-MFA SCAP scan — DC01: **42.66%** (CAT I fail: 9, CAT II: 110, CAT III: 6)
- ✅ After-MFA SCAP scan — WS01: **42.20%** (CAT I fail: 9, CAT II: 111, CAT III: 6)
- ✅ After-MFA results staged in `Compliance-Reports/After-MFA/`
- ✅ `Compliance-Reports/README.md` scoring table updated with real numbers

### Optional Compliance Evidence

- ⬜ Nessus Essentials — credentialed scan (free, up to 16 IPs)
- ⬜ STIG Viewer — open .ckl files, review CAT I findings, document false positives
- ⬜ PKI health check baseline — run `Monitor-PKIHealth.ps1`

---

## RMF Templates ✅ Populated

- ✅ `Architecture/RMF-Templates/SAR-Template.md` — real scores, controls assessment, risk summary
- ✅ `Architecture/RMF-Templates/POAM-Template.md` — 18 CAT I / 221 CAT II / 12 CAT III tracked
- ✅ `Architecture/RMF-Templates/SSP-Template.md` — hostnames, roles, scan results, ATO pending
- ✅ `Architecture/RMF-Templates/Annual-STIG-Rescan-SOP.md` — 2026 baseline row populated

### Still Needs Input

- ✅ **AO name and signature** — filled in SSP and SAR (Glenn Byron, System Owner / Lab Program Manager, Self-Assessed Lab)
- ⬜ **Nessus Essentials scan** — adds vulnerability evidence; results go in SAR § 7 and POAM
- ⬜ **IIS STIG assessment** — CRL/AIA server; referenced as pending in all four templates
- ⬜ **STIG Viewer CAT I review** — open .ckl files, document false positives, update POAM rows

---

## Physical Laptop — Add to Lab

Guide: `Lab-Kit/06-PhysicalEndpoint/Add-Physical-Laptop.md`

- ✅ Windows 11 confirmed
- ✅ TPM 2.0 confirmed — VSC ready
- ⬜ Create External virtual switch in Hyper-V
- ⬜ Domain-join laptop to lab.local
- ⬜ Apply smart card GPO (`gpupdate /force`)
- ⬜ Create Virtual Smart Card (`tpmvscmgr.exe`)
- ⬜ Enroll VSC certificate via `New-TokenEnrollment.ps1`
- ⬜ Test smart card logon on real hardware — **take screenshots here**
- ✅ Run SCAP SCC scan with Windows 11 STIG benchmark — **DONE 2026-06-02** — WO02 scanned against `Microsoft_Windows_11_STIG-2.3.9` (MAC-1 Classified profile): **37.00%** compliance (13 CAT I open, 122 CAT II, 8 CAT III). Results staged in `Compliance-Reports/Laptop/After-SmartCard/2026-06-02_104513/`
- ⬜ Test VPN from physical laptop (EAP-TLS, no password)

---

## Portfolio Finalization

- ⏳ Add real screenshots to `Demo-Walkthrough.md` — **1 of 9 captured** (PIN entry on Lab-WS01)
      Captured: `02-pin-entry-cert-subject.png`, `02b-incorrect-pin-validation.png` (supplement), plus 2 portfolio-evidence shots
      Still pending: lock screen (slot 1), Event 4768 (slot 3), session lock (slot 4), VPN connected (slot 5), PKI dashboard (slot 6), SCAP delta (slot 7), Win11 STIG result on WO02 (slot 8)
      See `Screenshots/README.md` for the capture checklist
- ⬜ Update Portfolio/ Word docs with After-MFA scores (DC01: 42.66% / WS01: 42.20%)
- ⬜ Run full Ansible STIG hardening pass — improves scores before final portfolio push
- ⬜ Final `Scrub-Repo.ps1 -WhatIf` pass before any push

---

## Phase 8 — Zero Trust Extension ⬜ Scripts Pending

Design: `Architecture/Roadmap/CAC_PIV_Phase8_ZeroTrust_Extension.md`
Gap analysis: `Architecture/CAC_PIV_Program_ZeroTrust_Gap_Analysis.md`

### 8.1 — Authorization & Least Privilege
- ⬜ `Set-TieredAdminModel.ps1` — AD admin tiering (Tier 0/1/2)
- ⬜ `Set-LeastPrivilegeGPO.ps1` — User Rights Assignment hardening
- ⬜ `New-RBACModel.ps1` — role groups, role → resource mapping
- ⬜ `Set-AuthenticationPolicySilo.ps1` — Kerberos Authentication Policy Silos
- ⬜ `Deploy-ResourceGateway.ps1` — reverse proxy as working PEP demo

### 8.2 — Device Trust
- ⬜ `New-DeviceCertTemplate.ps1` — machine cert template from Issuing CA
- ⬜ `Enroll-DeviceCertificates.ps1` — device cert autoenrollment
- ⬜ `Set-DeviceComplianceCheck.ps1` — posture gate (AV, patch, BitLocker)
- ⬜ `Update-VPN-DeviceAuth.ps1` — require user + machine certs on VPN

### 8.3 — Continuous & Conditional Access
- ⬜ `Set-KerberosTicketLifetime.ps1` — shorten TGT/TGS lifetimes
- ⬜ `Deploy-ConditionalAccess.ps1` — PIV federation into Entra ID / AD FS
- ⬜ `New-RiskPolicy.ps1` — step-up auth and deny conditions

### 8.4 — Workload / Non-Person Identity *(optional)*
- ⬜ `New-WorkloadCertTemplate.ps1` — short-lived service identity cert template
- ⬜ `Set-ServiceAccountHardening.ps1` — convert to gMSA, remove stored secrets
- ⬜ `Enable-mTLS.ps1` — mutual TLS between two lab services

### 8.5 — Network Segmentation
- ⬜ `Set-Microsegmentation.ps1` — default-deny east-west between lab VMs
- ⬜ `Convert-VPNToPerApp.ps1` — per-resource VPN access (ZTNA-style)

### 8.6 — Visibility → Decisioning
- ⬜ `Deploy-SIEM.ps1` — forward WEF stream into Sentinel or Elastic
- ⬜ `New-DetectionRules.ps1` — anomalous auth, lateral movement detections
- ⬜ `Connect-Analytics-To-Policy.ps1` — risk signal feeds conditional access

### 8.7 — Validation & Evidence
- ⬜ `Invoke-ZeroTrustValidation.ps1` — extend 7-layer validator with ZT checks
- ⬜ Extend `Stage-Reports.ps1` with Before-ZT / After-ZT delta
- ⬜ `Demo-Walkthrough-ZT.md`

---

## Phase 9 — Azure Cloud VPN + Conditional Access ⬜ Not Started

Design: `Architecture/Roadmap/CAC_PIV_Phase9_Azure_VPN_ConditionalAccess.md`
Requires: Azure for Students + free M365 Developer tenant.

- ⬜ 9.0 — Cost guardrail + resource group (always first)
- ⬜ 9.1 — Entra tenant + test users + MFA enrollment
- ⬜ 9.2 — Azure P2S VPN Gateway authenticated by your Issuing CA certs
- ⬜ 9.3 — Conditional Access policies (MFA + compliant device)
- ⬜ 9.4 — Device compliance signal (Entra join + Intune)
- ⬜ 9.5 — Sign-in logs + detections
- ⬜ 9.6 — Validation + teardown (run `Remove-AzureLabResources.ps1` every session)

---

## Phase 9B — On-Prem VPN Appliance ⬜ Not Started

Design: `Architecture/Roadmap/CAC_PIV_Phase9B_OnPrem_VPN_Appliance.md`
Requires: Dell 3080 Micro #2 + OPNsense.

- ⬜ 9B.1 — Hardware + network prep
- ⬜ 9B.2 — OPNsense base install + hardening
- ⬜ 9B.3 — Issue server + client certs from your Issuing CA
- ⬜ 9B.4 — VPN profile, cert-auth test, negative test (revoked cert)
- ⬜ 9B.5 — Syslog forwarding to Splunk (ties into CySA+ lab)
- ⬜ 9B.6 — Validation + evidence

---

## Phase Summary

| Phase | Status |
|-------|--------|
| 1 — Foundation & Architecture | ✅ Complete |
| 2 — Core Automation Scripts | ✅ Complete |
| 3 — Compliance & Regulatory Docs | ✅ Complete |
| 4 — Lab Execution (SCAP Scans) | ✅ Complete |
| 5 — RMF Authorize | ✅ Templates populated · AO signature pending |
| 6 — Advanced Automation | ✅ Complete |
| 7 — Portfolio Finalization | ⬜ Waiting on laptop screenshots |
| 8 — Zero Trust Extension | ⬜ Design done · scripts pending |
| 9 — Azure Cloud VPN | ⬜ Design done · not started |
| 9B — On-Prem VPN Appliance | ⬜ Design done · hardware needed |

---

*Build sequence: `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md`*
*RMF templates: `Architecture/RMF-Templates/`*
*Phase 8–9B design: `Architecture/Roadmap/`*
*Laptop guide: `Lab-Kit/06-PhysicalEndpoint/Add-Physical-Laptop.md`*
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                  