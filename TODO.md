# CAC Program — Outstanding Tasks

**Author:** Glenn Byron
**Last Updated:** June 4, 2026

Living task list for the CAC/PIV ICAM portfolio project.
✅ Complete · ⬜ Needs hands-on work · ⏳ In progress

---

## Security Posture

- ✅ **Repo is public again** (2026-06-03), but the lab admin password is **still treated as sensitive** and gets scrubbed before push.
- ✅ **Lab admin password is kept stable** (no rotation) — same string used by `Unattend-Server.xml` and all local docs. Real value lives in `.scrub-patterns.local.json` and is replaced with `<LAB-ADMIN-PASSWORD>` at push time by `Scrub-Repo.ps1`.
- ✅ **Pre-add scan workflow** — `security/scripts/Scan-LocalRepo.ps1` runs against new files before they're committed (catches leaks of real org names, emails, and the lab password before they ship)
- ✅ `.scrub-patterns.local.json` cleaned up — duplicate-case keys removed (was causing JSON parse error in both `Scrub-Repo.ps1` and the scanner), dotless subnet pattern removed (was generating false positives). Scanner now parses via `ConvertFrom-Json` cleanly.
- ✅ Scanner shows per-pattern `[CLEAN]`/`[LEAK]` status block so each pattern is visibly checked.

---

## Milestones

- ✅ **GitHub repo topics added** — `identity-management`, `pki`, `smart-card`, `fido2`, `active-directory`, `certificate-authority`, `nist-800-53`, `fips-201`, `zero-trust`, `icam`, `ad-cs`, `powershell`, `disa-stig`, `hyper-v`, `rmf`, `cac`
- ✅ **v1.0 pushed** (2026-06-03) — two-tier PKI + smart card MFA on physical endpoint + SCAP evidence (DC01 42.66% / WS01 42.20% / WO02 37.00%) + Phase 8 Zero Trust extension (8 full scripts + 13 scaffolds + Demo-Walkthrough-ZT.md)
- ⬜ **Write GitHub release notes** — Releases → Draft new release → pick `v1.0` tag → paste bullet list (PKI, smart card, SCAP, ZT extension, card-blocked items deferred to v1.1)
- ⬜ **v1.1 (when cards arrive)** — slot 1/4/5 screenshots, VPN EAP-TLS test, `Card-Test-Matrix.md` filled in, optional Ansible STIG hardening pass to push compliance % up

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
- ✅ PKI health check baseline — `Monitor-PKIHealth.ps1` run 7x on 2026-06-04 (audit log + 12:18:49 dashboard screenshot staged in `Compliance-Reports/PKI-Health/2026-06-04/`)

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

## Physical Laptop (WO02) — Add to Lab

Guide: `Lab-Kit/06-PhysicalEndpoint/Add-Physical-Laptop.md`

- ✅ Windows 11 confirmed
- ✅ TPM 2.0 confirmed — VSC ready
- ✅ External virtual switch created — DC01 dual-NIC (10.10.10.0/24 LabInternal + 10.10.20.0/24 External)
- ✅ Domain-joined to lab.local — computer object at `CN=WO02,OU=Workstations`
- ✅ Smart card GPO applied (`scforceoption=1`, `ScRemoveOption=1`, `InactivityTimeoutSecs=900`)
- ✅ Virtual Smart Card created via `tpmvscmgr.exe`
- ✅ VSC certificate enrolled for `LAB\labtech` via `New-TokenEnrollment.ps1` (RA + Issuer ceremony, AC-5 satisfied)
- ✅ Smart card logon confirmed working on real hardware (RDP to 10.10.20.30, PIN entry, desktop reached)
- ✅ **Event 4768 Pre-Auth Type 16 captured** — PKINIT confirmed at protocol level (logged in `Lab-Kit/LAB-BUILD-CHANGELOG.md`)
- ✅ Run SCAP SCC scan with Windows 11 STIG benchmark — **DONE 2026-06-02** — WO02 against `Microsoft_Windows_11_STIG-2.3.9` (MAC-1 Classified profile): **37.00%** compliance (13 CAT I open, 122 CAT II, 8 CAT III). Results staged in `Compliance-Reports/Laptop/After-SmartCard/2026-06-02_104513/`
- ⬜ Test VPN from physical laptop (EAP-TLS, no password) — *needed to fill Demo-Walkthrough slot 5*
- ✅ Checkpoint taken — `06-WO02-SmartCard-Working`

---

## Portfolio Finalization

- ✅ Portfolio Word docs updated with all three After-MFA scores (DC01 42.66% / WS01 42.20% / WO02 37.00%) — "SCAP Compliance Snapshot" section + results table + interpretation paragraph + source citation added to `CAC-Program-Showcase-GlennByron.docx` and `Federal_Upgrade_Path.docx` (2026-06-03)
- ✅ `SCAP-Workflow-QuickRef.md` promoted from `Dispatch/` to `Lab-Kit/05-Compliance/` — stale `192.168.1.10` fixed to `10.10.10.10` / `Lab-DC01`. Docker `scap-summary` moved to "Optional Enhancements" at bottom (deferred until DC hardening pass)
- ⏳ **Screenshots — 6 of 8 staged**
    - ✅ Slot 2 — `02-pin-entry-cert-subject.png` (PIN prompt)
    - ✅ Slot 2b — `02b-incorrect-pin-validation.png` (incorrect PIN dialog)
    - ✅ Slot 3 — `03-pkinit-validation-table.png` (Event 4768 annotated)
    - ✅ Slot 6 — `06-pki-health-dashboard.png` (Monitor-PKIHealth.ps1 on Lab-DC01, 2026-06-04 12:18:49, ALL CHECKS PASSED)
    - ✅ Slot 7 — `07-scap-before-after-side-by-side.png` (DC01 44.95% → 42.66%)
    - ✅ Slot 8 — `08-scap-win11-stig-result.png` (SCC Summary Viewer, WO02)
    - ⬜ Slot 1 — lock screen smart-card-only (**card-blocked** — v1.1)
    - ⬜ Slot 4 — session lock on card removal w/ stopwatch (**card-blocked** — v1.1)
    - ⬜ Slot 5 — VPN connected EAP-TLS (**card-blocked** — v1.1)
    - ⬜ *(optional v1.1 polish)* parameterized PKI health run with `-CRLUrls`/`-OCSPUrl`/`-IssuingCAServer` populated → captures all-green `[OK]` rows instead of `[SKIP]`
- ⬜ Run full Ansible STIG hardening pass — pushes scores up before v1.1
- ⬜ Final `Scrub-Repo.ps1 -WhatIf` pass before any push

---

## Card Hardware Testing — Waiting on Amazon Order

Test buy planned: 2 x YubiKey 5 NFC (~$110) + 1-2 x Hirsch uTrust FIDO2 FIPS Card (~$25 each) + spare Identiv reader if needed.

- ⬜ Order test cards from Amazon (Yubico storefront + Identiv)
- ⬜ Run `certutil -scinfo` on Hirsch card to confirm PIV applet is loaded (the FIDO2-only listing may or may not include PIV)
- ⬜ Email Hirsch Sales for bulk-order quote + confirm PIV applet on UPC 721755006139
- ⬜ Test PIV enrollment on YubiKey 5 NFC via `New-YubiKeyToken.ps1` or `certreq` INF method
- ⬜ Test FIDO2 on YubiKey via WebAuthn.io (smoke test)
- ⬜ Test FIDO2 on Hirsch card via WebAuthn.io
- ⬜ Test smart card logon to `lab.local` with each card type
- ⬜ Document findings in `Lab-Kit/Reference/Card-Test-Matrix.md` (form factor × PIV × FIDO2 × bulk price × reset workflow)
- ⬜ Update `Federal_Upgrade_Path.docx` with FIPS 140-3 / AAL3 / TAA / CJIS evidence from Hirsch card

---

## Phase 8 — Zero Trust Extension

Design: `Architecture/Roadmap/CAC_PIV_Phase8_ZeroTrust_Extension.md`
Gap analysis: `Architecture/CAC_PIV_Program_ZeroTrust_Gap_Analysis.md`
**Location: `Lab-Kit/07-ZeroTrust/`** (own folder, see its README for the full index)

### 8.1 — Authorization & Least Privilege
- ✅ `Set-TieredAdminModel.ps1` — AD admin tiering (Tier 0/1/2). **FULL** — ready to run.
- ✅ `Set-LeastPrivilegeGPO.ps1` — User Rights Assignment GPOs per tier with cross-tier deny. **FULL** — ready to run.
- ⚙ `New-RBACModel.ps1` — role groups + role→resource mapping. **SCAFFOLD** — edit example role array to your real roles.
- ✅ `Set-AuthenticationPolicySilo.ps1` — Kerberos Auth Policy Silos enforcing tier isolation. **FULL** — ready to run.
- ⚙ `Deploy-ResourceGateway.ps1` — PEP reverse-proxy demo. **SCAFFOLD** — needs IIS ARR / nginx / Caddy choice.

### 8.2 — Device Trust
- ✅ `New-DeviceCertTemplate.ps1` — `ZT-Device-Authentication` template (RSA 2048, 1yr). **FULL** — ready to run.
- ✅ `Enroll-DeviceCertificates.ps1` — autoenroll GPO + fleet pulse. **FULL** — ready to run.
- ⚙ `Set-DeviceComplianceCheck.ps1` — AV/patch/BitLocker/firewall posture → extensionAttribute1. **SCAFFOLD** — wire to your AV.
- ⚙ `Update-VPN-DeviceAuth.ps1` — two-cert VPN. **SCAFFOLD** — VPN-product-dependent.

### 8.3 — Continuous & Conditional Access
- ✅ `Set-KerberosTicketLifetime.ps1` — TGT 4h / TGS 10m. **FULL** — ready to run.
- ⚙ `Deploy-ConditionalAccess.ps1` — Entra CA + PIV federation. **SCAFFOLD** — overlaps Phase 9.
- ⚙ `New-RiskPolicy.ps1` — step-up/deny on risk signal. **SCAFFOLD** — depends on risk source.

### 8.4 — Workload / Non-Person Identity *(optional)*
- ⚙ `New-WorkloadCertTemplate.ps1` — **SCAFFOLD**
- ⚙ `Set-ServiceAccountHardening.ps1` — gMSA conversion. **SCAFFOLD**
- ⚙ `Enable-mTLS.ps1` — mTLS between two lab services. **SCAFFOLD**

### 8.5 — Network Segmentation
- ✅ `Set-Microsegmentation.ps1` — Windows Firewall GPO, default-deny east-west on Tier 1/2. **FULL** — ready to run (test with `-WhatIf` first!).
- ⚙ `Convert-VPNToPerApp.ps1` — broker-based ZTNA. **SCAFFOLD** — needs broker product choice.

### 8.6 — Visibility → Decisioning
- ⚙ `Deploy-SIEM.ps1` — **SCAFFOLD** — Splunk Free vs Sentinel vs Elastic.
- ⚙ `New-DetectionRules.ps1` — 6 starter rule names listed. **SCAFFOLD**
- ⚙ `Connect-Analytics-To-Policy.ps1` — closes the loop. **SCAFFOLD**

### 8.7 — Validation & Evidence
- ✅ `Invoke-ZeroTrustValidation.ps1` — 7-layer ZT validator (L8-L14) with grade. **FULL** — ready to run.
- ✅ `Demo-Walkthrough-ZT.md` — companion to the Phase 4 demo walkthrough. Live-demo script for the ZT controls.
- ⬜ Extend `Stage-Reports.ps1` with Before-ZT / After-ZT delta (small follow-on)

**Status:** 8 full implementations + 13 scaffolds + 2 docs. Run order in `Lab-Kit/07-ZeroTrust/README.md`. Scaffolds become turnkey once you pick the product (SIEM, broker, etc.).

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
| 4 — Lab Execution (SCAP Scans) | ✅ Complete (DC01 + WS01 + WO02 all scanned) |
| 5 — RMF Authorize | ✅ Templates populated · AO signature pending |
| 6 — Advanced Automation | ✅ Complete |
| 7 — Portfolio Finalization | ⏳ Portfolio docs ✅ · 6 of 8 screenshots staged · 3 card-blocked → v1.1 |
| 8 — Zero Trust Extension | ✅ 8 full scripts + 13 scaffolds + Demo-Walkthrough-ZT.md shipped in v1.0 |
| 9 — Azure Cloud VPN | ⬜ Design done · not started |
| 9B — On-Prem VPN Appliance | ⬜ Design done · hardware needed |
| Card Hardware Testing | ⬜ Waiting on Amazon order (YubiKey + Hirsch FIDO2) |

---

## Recent Wins (2026-06-02 to 06-04)

- ✅ WO02 physical laptop end-to-end — domain join, VSC, smart card logon, Event 4768 Type 16 PKINIT captured
- ✅ WO02 Windows 11 STIG scan staged (37.00% baseline, 13 CAT I / 122 CAT II / 8 CAT III)
- ✅ Phase 8 Zero Trust shipped — 8 full scripts + 13 scaffolds + `Demo-Walkthrough-ZT.md`
- ✅ Lab lifecycle scripts: `Export-LabVMs.ps1`, `Import-LabVM.ps1`, `Get-LabVMSize.ps1`
- ✅ Sanitized `Lab-Kit/Reference/` (ONBOARDING + TROUBLESHOOTING) synced from lab export
- ✅ Subnet drift fixed across repo (10.10.10.x / 10.10.20.x)
- ✅ Git history rewritten + repo gated by `Scrub-Repo.ps1` + local `Scan-LocalRepo.ps1` with per-pattern `[CLEAN]`/`[LEAK]` block
- ✅ `v1.0` tagged and pushed to public GitHub (2026-06-03)
- ✅ Slot 6 PKI dashboard captured (2026-06-04 12:18:49) — `ALL CHECKS PASSED`; staged with audit-log evidence under `Compliance-Reports/PKI-Health/2026-06-04/`
- ✅ **Real-world deployment hardening** — `Monitor-PKIHealth.ps1` and `Set-AuthenticationPolicySilo.ps1` patched against PS 5.1 `AutomationNull.Count` crash and `Grant-ADAuthenticationPolicySiloAccess` group-object rejection (both found by running on Lab-DC01, not theoretical)
- ✅ **Lab-export sync — `Live-Servers/` + `Tools-Kit/` imported** — net-new folders from the lab kit (production-deployment readiness/GPO compliance helpers + tool downloaders); both clean of sensitive patterns, no scrubbing needed. README table entries were forward-declared; now backed by actual files.
- ✅ **Stale top-level `TROUBLESHOOTING.md` removed** — was a strict subset of `Lab-Kit/Reference/TROUBLESHOOTING.md`; README link updated to point at the canonical Reference/ copy.
- ✅ **WALKTHROUGH.md gap closed** — Step 3b (create Workstations OU + scope `scforceoption=1` GPO to it, BEFORE domain join) merged into Phase 6 from lab export. Closes the silent landmine where readers would link the smart-card GPO at domain root by default and lock out Lab-DC01. Includes built-in safety check that auto-removes accidental domain-root link.

---

*Build sequence: `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md`*
*RMF templates: `Architecture/RMF-Templates/`*
*Phase 8–9B design: `Architecture/Roadmap/`*
*Laptop guide: `Lab-Kit/06-PhysicalEndpoint/Add-Physical-Laptop.md`*
