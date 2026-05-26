# CAC Program — Outstanding Tasks

**Author:** Glenn Byron
**Last Updated:** May 24, 2026

This is the living task list for the CAC/PIV ICAM portfolio project. Items marked ✅ are complete. Items marked ⬜ require hands-on work by Glenn. Items marked 📋 are blocked until Phase 4 lab data exists.

---

## Immediate — Before the Next Push

- ⬜ **Commit the Phase 6 session work** — the full commit message is in the last Claude session. Close VS Code or any git GUI first if the index.lock error appears, then run the `git add` and `git commit` commands from PowerShell.
- ⬜ **Run Scrub-Repo.ps1 before pushing**
  ```powershell
  .\Scrub-Repo.ps1 -WhatIf   # preview first
  .\Scrub-Repo.ps1            # apply
  git diff                    # review
  ```
- ⬜ **Push to GitHub**
  ```powershell
  git push
  ```
- ⬜ **Confirm GitHub Actions pass** — check the Secret Scan and PowerShell Lint badges turn green after the push.

---

## One-Time Setup (if not already done)

- ✅ `.scrub-patterns.local.json` created from the example file and filled in with real identifiers
- ✅ `.idea/` removed from git tracking (`git rm -r --cached .idea/` was run)
- ⬜ **Add GitHub repo topics** — go to the repo page on GitHub, click the gear icon next to "About", and add:
  ```
  identity-management  pki  smart-card  fido2  active-directory
  certificate-authority  nist-800-53  fips-201  zero-trust  icam
  ad-cs  watchguard  entra-id  powershell  nist-csf  cisa-cpg
  regulatory-compliance
  ```

---

## Phase 4 — Lab Execution (Requires Running VMs)

This is the remaining hands-on work. All scripts are written and ready. Follow `Lab-Kit/LAB-DAY-CHECKLIST.md` for the full step-by-step sequence.

### VM Setup
- ⬜ Spin up three Hyper-V VMs using `Lab-Kit\01-HyperV-Host\New-LabVMs.ps1`
- ⬜ Install Windows Server on each VM (use `Lab-Kit\01-HyperV-Host\Unattend-Server.xml` for hands-free install)
- ⬜ Run `Lab-Kit\01-HyperV-Host\Set-VMPostConfig.ps1` on each VM after OS install
- ⬜ Take baseline checkpoint: `New-LabSnapshot.ps1 -Mode Create -Label "00-BaseOS"`

### Offline Root CA
- ⬜ Transfer `Lab-Kit\02-OfflineRootCA\` to the air-gapped OfflineRootCA VM via PowerShell Direct
- ⬜ Run `Download-OfflineCA-Kit.ps1` on the VM to stage prerequisites
- ⬜ Run `Initialize-OfflineRootCA.ps1` — 8-step guided ceremony (installs CA role, configures Root CA, publishes CRL, exports cert+CRL)
- ⬜ Transfer Root CA cert and CRL back to DC01 via PowerShell Direct

### Domain Controller & PKI
- ⬜ Run `Build-CAC-Lab.ps1` — promotes DC, reboots
- ⬜ Run `Build-CA-GPO.ps1` — Issuing CA + smart card GPO (after reboot)
- ⬜ Run `New-CertificateTemplates.ps1` — creates SmartCardLogon and Admin cert templates
- ⬜ Run `Set-OCSPResponder.ps1` — OCSP role install and signing cert request
- ⬜ Run `Set-AuditLogForwarding.ps1` — audit policy and WEF configuration
- ⬜ Take checkpoint: `New-LabSnapshot.ps1 -Mode Create -Label "02-PKI-Ready"`

### Token Enrollment
- ⬜ Run `New-TokenEnrollment.ps1` in RA mode (as Registration Authority)
- ⬜ Run `New-TokenEnrollment.ps1` in Issuer mode (as a different account — confirms SOD block)
- ⬜ (Optional) Run `New-YubiKeyToken.ps1` if testing YubiKey provisioning

### Workstation
- ⬜ Domain-join Lab-Workstation01
- ⬜ Run `Enforce-SmartCard.ps1` on the workstation
- ⬜ Run `Deploy-VPNClient.ps1` to configure the IKEv2 VPN profile

### SCAP SCC Scans
- ⬜ Download tools: `Tools-Kit\Get-LabTools.ps1`
- ⬜ Install SCAP SCC from `C:\FedCompliance-Tools\00-SCAP-SCC\`
- ⬜ Run **Before-MFA** baseline scan — export HTML + XCCDF XML
- ⬜ Stage results: `Lab-Kit\05-Compliance\Stage-Reports.ps1` (option 1)
- ⬜ Apply GPO hardening, reboot
- ⬜ Run **pre-scan validation**: `Invoke-LabValidation.ps1` — confirm all 7 layers pass
- ⬜ Run **After-MFA** hardened scan — export HTML + XCCDF XML
- ⬜ Stage results: `Stage-Reports.ps1` (option 2)
- ⬜ Note before/after compliance % and CAT I counts for the SAR

### STIG Viewer Checklists
- ⬜ Install DISA STIG Viewer from `C:\FedCompliance-Tools\01-STIG-Viewer\`
- ⬜ Complete Windows Server 2022 STIG checklist (.ckl)
- ⬜ Complete Active Directory Domain Services STIG checklist
- ⬜ Complete AD CS / PKI STIG checklist
- ⬜ Complete IIS 10.0 STIG checklist (if using IIS for CRL/AIA)
- ⬜ Export all .ckl files → `Compliance-Reports\After-MFA\`

### Nessus Essentials
- ⬜ Activate Nessus Essentials at tenable.com (free, email-gated)
- ⬜ Run credentialed before-hardening scan → `Compliance-Reports\Before-MFA\Baseline-Vulnerability.pdf`
- ⬜ Run credentialed after-hardening scan → `Compliance-Reports\After-MFA\Hardened-Vulnerability.pdf`

### Demo Screenshots (for Demo-Walkthrough.md)
- ⬜ Lock screen showing smart card prompt only — no password field
- ⬜ PIN entry prompt with cardholder name and certificate subject visible
- ⬜ Event Viewer showing Event 4768 with Pre-Auth Type 16
- ⬜ Locked screen immediately after card removal (with timer visible)
- ⬜ VPN connected status — no password prompt
- ⬜ `Monitor-PKIHealth.ps1` output showing all green
- ⬜ SCAP before and after HTML reports side by side

---

## Phase 5 — RMF Authorize (Blocked on Phase 4 Data)

All templates are written. These items need real scan data to complete.

- 📋 Populate `Architecture/RMF-Templates/SAR-Template.md` with before/after SCAP scores, CAT I/II counts, Nessus finding counts
- 📋 Populate `Architecture/RMF-Templates/POAM-Template.md` with open findings from the After-MFA scan and remediation schedule
- 📋 Populate `Architecture/RMF-Templates/SSP-Template.md` with actual compliance score and ATO decision block
- 📋 Update `Compliance-Reports/README.md` with real SCAP SCC compliance % and Nessus counts
- 📋 Update `STATUS.md` Phase 4 checkboxes to ✅ and change phase row to Complete
- 📋 Run CSET assessment and record results in `Architecture/RMF-Templates/CSET-Assessment-Guide.md`

---

## Phase 7 — Portfolio Finalization (After Phase 4)

- 📋 Add real screenshots to `Demo-Walkthrough.md`
- 📋 Update `Portfolio/` with final versions of recruiter-facing documents
- 📋 Final pass of `Scrub-Repo.ps1` before public push
- 📋 Confirm all CI badges are green (Secret Scan + PowerShell Lint)

---

## Automation — Fully Complete ✅

Everything that can be scripted has been scripted. No further code work needed before lab execution.

| Phase | Status |
|-------|--------|
| Phase 1 — Foundation & Architecture | ✅ Complete |
| Phase 2 — Core Automation Scripts | ✅ Complete |
| Phase 3 — Compliance & Regulatory Docs | ✅ Complete |
| Phase 4 — RMF Assess (Lab Execution) | ⬜ Pending lab work |
| Phase 5 — RMF Authorize (Templates) | ✅ Templates done / 📋 data pending |
| Phase 6 — Advanced Automation | ✅ Complete |
| Phase 7 — Portfolio Finalization | 📋 After Phase 4 |

---

*Full execution sequence: `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md`*
*RMF template population: `Architecture/RMF-Templates/`*
*Demo guide: `Demo-Walkthrough.md`*
