# CAC Program — Outstanding Tasks

**Author:** Glenn Byron
**Last Updated:** June 3, 2026

Living task list for the CAC/PIV ICAM portfolio project.
✅ Complete · ⬜ Needs hands-on work · ⏳ In progress

---

## Security Posture

- ✅ **Repo is public again** (2026-06-03), but the lab admin password is **still treated as sensitive** and gets scrubbed before push.
- ✅ **Lab admin password is kept stable** (no rotation) — same string used by `Unattend-Server.xml` and all local docs. Real value lives in `.scrub-patterns.local.json` and is replaced with `<LAB-ADMIN-PASSWORD>` at push time by `Scrub-Repo.ps1`.
- ✅ **Pre-add scan workflow** — `security/scripts/Scan-LocalRepo.ps1` runs against new files before they're committed (catches leaks of real org names, emails, and the lab password before they ship)
- ⬜ Fix `.scrub-patterns.local.json` so `Scrub-Repo.ps1` can parse it. PowerShell's `ConvertFrom-Json` is case-insensitive, so the lowercase and mixed-case versions of your org name collide. Delete the lowercase-only key (the org-domain key and the mixed-case key together cover every real case). Also delete the dotless `<subnet-without-trailing-dot>` line — it generates false positives by matching inside the safe lab subnet.

---

## Immediate — Do These Now (after rotation)

- ✅ **Add GitHub repo topics** — log in as glennbyron1, repo page → gear icon next to "About":
  ```
  identity-management  pki  smart-card  fido2  active-directory
  certificate-authority  nist-800-53  fips-201  zero-trust  icam
  ad-cs  powershell  disa-stig  hyper-v  rmf  cac
  ```
- ⬜ **Tag v1.0 release** — *do this only after final clean push goes public; tags are immutable*:
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

- ⏳ Add real screenshots to `Demo-Walkthrough.md` — **5 of 8 staged (slots 2, 2b, 3, 7, 8)**
      Staged in `Screenshots/`:
        - `02-pin-entry-cert-subject.png` (Lab-WS01 PIN prompt) — slot 2 ✅
        - `02b-incorrect-pin-validation.png` (incorrect PIN dialog) — slot 2 supplement ✅
        - `03-pkinit-validation-table.png` (Event 4768 annotated) — slot 3 ✅
        - `07-scap-before-after-side-by-side.png` (DC01 44.95% → 42.66%) — slot 7 ✅
        - `08-scap-win11-stig-result.png` (SCC Summary Viewer for WO02) — slot 8 ✅
        - 2 portfolio-evidence shots (enrollment ceremony success + pre-kerberos troubleshoot)
      Still pending — **CARD-BLOCKED until Amazon order arrives (~1 week):** lock screen (slot 1), session lock with stopwatch (slot 4), VPN connected (slot 5)
      Still pending — **not blocked, can do anytime:** PKI dashboard (slot 6)
- ✅ Update Portfolio/ Word docs with all three After-MFA scores (DC01: 42.66% / WS01: 42.20% / WO02: 37.00%) — added "SCAP Compliance Snapshot" section + 4-column results table + interpretation paragraph + source citation to `CAC-Program-Showcase-GlennByron.docx` and `Federal_Upgrade_Path.docx` (2026-06-03)
- ✅ `SCAP-Workflow-QuickRef.md` promoted from `Dispatch/` (gitignored) to `Lab-Kit/05-Compliance/`. Fixed stale `192.168.1.10` reference → `10.10.10.10`/`Lab-DC01`. Docker `scap-summary` references moved to a bottom "Optional Enhancements" section (deferred until DC hardening pass)
- ✅ Local scanner enhanced — `security/scripts/Scan-LocalRepo.ps1` now prints per-pattern `[CLEAN]`/`[LEAK]` status block so every pattern shows it was actually checked. `.scrub-patterns.local.json` cleaned up (duplicate-case keys removed, dotless 10.10.11 false-positive pattern removed)
- ⬜ Run full Ansible STIG hardening pass — improves scores before final portfolio push
- ⬜ Final `Scrub-Repo.ps1 -WhatIf` pass before any push
- ⬜ Tag `v1.0` and write GitHub Release notes (lab is at a clean milestone; card-blocked items documented for v1.1)

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
| 7 — Portfolio Finalization | ⏳ 5 screenshots + VPN test + portfolio docx updates remaining |
| 8 — Zero Trust Extension | ⬜ Design done · scripts pending |
| 9 — Azure Cloud VPN | ⬜ Design done · not started |
| 9B — On-Prem VPN Appliance | ⬜ Design done · hardware needed |
| Card Hardware Testing | ⬜ Waiting on Amazon order (YubiKey + Hirsch FIDO2) |

---

## Recent Wins (2026-06-02 to 06-03)

- ✅ WO02 physical laptop end-to-end working — domain join, VSC, smart card logon
- ✅ Event 4768 Pre-Auth Type 16 PKINIT confirmed at protocol level (primary IA-2(11) evidence)
- ✅ WO02 Windows 11 STIG scan staged (37% baseline)
- ✅ Lab-Kit/Reference/ created with sanitized ONBOARDING.md + TROUBLESHOOTING.md
- ✅ Three new lab lifecycle scripts: `Export-LabVMs.ps1`, `Import-LabVM.ps1`, `Get-LabVMSize.ps1`
- ✅ Subnet drift fixed across repo (10.10.10.x / 10.10.20.x)
- ✅ Pack-LabKit.ps1 hardened (BOM, encoding, IDE exclusion, truncation)
- ✅ History rewrite + force-push to private GitHub (all 4 sensitive patterns purged from history)

---

*Build sequence: `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md`*
*RMF templates: `Architecture/RMF-Templates/`*
*Phase 8–9B design: `Architecture/Roadmap/`*
*Laptop guide: `Lab-Kit/06-PhysicalEndpoint/Add-Physical-Laptop.md`*
