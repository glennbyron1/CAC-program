# Lab Day Checklist — Phase 4 STIG Execution

**Author:** Glenn Byron
**Purpose:** Step-by-step execution guide for Phase 4 lab work. Complete these items to generate the real scan data needed to populate the Phase 5 RMF templates.

---

## Before You Start

- [ ] Hyper-V host is up, sufficient RAM available for 2–3 VMs simultaneously
- [ ] VMs snapshotted at clean state before any changes
- [ ] Internet access available on host (download tools if not already staged)
- [ ] USB drive ready if testing offline CA transfer workflow
- [ ] Log file location set: `C:\Windows\Logs\` on each VM

---

## Phase 4.1 — SCAP SCC Automated Scans

### Install SCAP SCC
- [ ] On the domain-joined VM, run:
  ```powershell
  .\Automation-Scripts\Download-FedCompliance-Kit.ps1 -OutputPath "C:\FedCompliance-Tools"
  ```
- [ ] Install SCAP SCC from `C:\FedCompliance-Tools\00-SCAP-SCC\`
- [ ] Confirm SCAP SCC opens and sees the local machine

### Before-MFA Baseline Scan
- [ ] VM is at clean state, no smart card GPOs applied yet
- [ ] In SCAP SCC: import SCAP 1.3 benchmarks from `C:\FedCompliance-Tools\03-SCAP-Content\`
- [ ] Select the Windows Server STIG XCCDF profile — use the **Server 2022** benchmark as the nearest available until DISA publishes a Server 2025 STIG (note which benchmark you used in Compliance-Reports/README.md)
- [ ] Run scan — takes 5–15 minutes
- [ ] Export results: HTML report + XCCDF XML
- [ ] Stage them:
  ```powershell
  .\Stage-Reports.ps1   # choose option 1 (Before-MFA)
  ```
- [ ] Note the compliance percentage and CAT I open count — you'll need these for the SAR

### Apply Hardening
- [ ] Run `Build-CAC-Lab.ps1` if not already done (domain build)
- [ ] Run `Build-CA-GPO.ps1` (CA + GPO deployment)
- [ ] Apply smart card GPOs from `Group-Policy\Enforce-SmartCard.ps1`
- [ ] Reboot VM

### After-MFA Hardened Scan
- [ ] Run SCAP SCC scan again (same benchmarks)
- [ ] Export results: HTML report + XCCDF XML
- [ ] Stage them:
  ```powershell
  .\Stage-Reports.ps1   # choose option 2 (After-MFA)
  ```
- [ ] Note the new compliance percentage — record in SAR-Template.md

---

## Phase 4.2 — STIG Viewer Checklists

- [ ] Install DISA STIG Viewer from `C:\FedCompliance-Tools\01-STIG-Viewer\`
- [ ] Import the After-MFA XCCDF XML into STIG Viewer
- [ ] Work through CAT I findings — mark each as Open, NotAFinding, or Not Applicable
- [ ] For NotApplicable: add rationale in the comment field
- [ ] Export completed .ckl file → `Compliance-Reports\After-MFA\`
- [ ] Repeat for:
  - [ ] Active Directory Domain Services STIG
  - [ ] PKI / AD CS Certificate Services STIG
  - [ ] IIS 10.0 STIG (if using IIS for CRL/AIA)

---

## Phase 4.3 — Nessus Essentials Scans

- [ ] Activate Nessus Essentials at tenable.com (free, email-gated activation)
- [ ] Install from `C:\FedCompliance-Tools\` (or download directly)
- [ ] Configure a credentialed scan: use domain admin credentials
- [ ] Run before-hardening scan → save PDF as `Compliance-Reports\Before-MFA\Baseline-Vulnerability.pdf`
- [ ] Run after-hardening scan → save PDF as `Compliance-Reports\After-MFA\Hardened-Vulnerability.pdf`
- [ ] Note Critical and High finding counts for each run

---

## Phase 4.4 — Token Enrollment Ceremony (Live Test)

- [ ] Have a second domain account ready to act as Card Issuer (not yourself)
- [ ] As Registration Authority, run:
  ```powershell
  .\Automation-Scripts\New-TokenEnrollment.ps1 -Mode RA -UserPrincipalName target@lab.local
  ```
- [ ] Complete the identity verification checklist in the script
- [ ] Confirm the AD extensionAttribute1 flag is set on the target user
- [ ] Switch to the Card Issuer account, run:
  ```powershell
  .\Automation-Scripts\New-TokenEnrollment.ps1 -Mode Issuer -UserPrincipalName target@lab.local
  ```
- [ ] Confirm the SOD block fires if you try to issue your own card
- [ ] Complete certificate enrollment and PIN set
- [ ] Screenshot: card login prompt, session lock on removal

---

## Phase 4.5 — PKI Health Check (Baseline Reading)

```powershell
.\Automation-Scripts\Monitor-PKIHealth.ps1 `
    -CRLUrls @("http://pki.lab.local/crl/RootCA.crl","http://pki.lab.local/crl/IssuingCA.crl") `
    -IssuingCAServer "ca01.lab.local"
```

- [ ] All CRL URLs reachable and within validity window
- [ ] Issuing CA cert expiry > 60 days
- [ ] Screenshot the green dashboard for portfolio evidence

---

## Phase 4.6 — VPN Live Test

- [ ] Smart card cert enrolled on test endpoint
- [ ] Run:
  ```powershell
  .\Automation-Scripts\Deploy-VPNClient.ps1 -VPNServerAddress "vpn.lab.local" -RunTest
  ```
- [ ] Connect VPN — confirm certificate auth, no password prompt
- [ ] Screenshot: VPN connected status, certificate subject in connection details

---

## After Lab Work — Fill In Templates

When scans are done, go fill in the real data in these files (all have [FILL IN] markers):

| File | What to fill in |
|------|----------------|
| `Architecture/SAR-Template.md` | Before/after SCAP scores, CAT I/II counts, Nessus crit/high counts |
| `Architecture/POAM-Template.md` | Real open findings from the After-MFA scan |
| `Architecture/SSP-Template.md` | Actual compliance score, ATO decision block |
| `Architecture/Annual-STIG-Rescan-SOP.md` | 2026 row in the assessment record table |
| `Architecture/CSET-Assessment-Guide.md` | 2026 assessment date and score, once CSET is run |
| `Compliance-Reports/README.md` | Real SCAP SCC compliance % and Nessus finding counts |

---

## Pre-Push Sanitization (Before Any Commit)

```powershell
# 1. Verify your local patterns file exists
Test-Path .scrub-patterns.local.json   # should return True

# 2. Preview what will be scrubbed
.\Scrub-Repo.ps1 -WhatIf

# 3. Apply scrub
.\Scrub-Repo.ps1

# 4. Review the diff
git diff

# 5. Commit
git add Compliance-Reports/ Architecture/
git commit -m "Phase 4 scan results — SCAP SCC and Nessus evidence"
git push
```

---

*When Phase 4 is done, update `STATUS.md` Phase 4 checkboxes and change the phase row to ✅ Complete.*
