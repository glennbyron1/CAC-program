# Annual STIG Re-Assessment — Standard Operating Procedure

Document ID: ARCH-ICAM-011
Author: Glenn Byron
Framework: NIST SP 800-53 CA-7, CM-6 | DISA RMF | DoD Instruction 8510.01

> **When to use this SOP:** Run annually (within 90 days of ATO expiration) and after any
> significant infrastructure change (new domain controller, CA re-key, OS version upgrade,
> new STIG content release). Results feed back into the POA&M and SSP.

---

## Overview

The annual STIG re-assessment serves two purposes: satisfying CA-7 continuous monitoring
requirements under the ATO, and catching configuration drift — settings that worked after
initial hardening but changed due to patches, admin activity, or software updates.

This SOP covers the full cycle: downloading current STIG content, running SCAP SCC scans,
comparing against the previous year's baseline, updating the POA&M, and documenting the
results for ATO renewal.

---

## 1. Pre-Assessment Preparation

Complete these steps before running any scans.

### 1.1 Download Current STIG Content

DISA releases updated STIGs quarterly. Always scan with the most current content — an
outdated XCCDF benchmark may miss new vulnerability checks or produce incorrect results.

```powershell
# Stage fresh STIG content and SCAP benchmarks
.\Automation-Scripts\Download-FedCompliance-Kit.ps1 -OutputPath "C:\FedCompliance-Tools"
```

Check the DISA STIG release page at `public.cyber.mil/stigs/downloads/` for any new
benchmark releases since your last assessment. Note the version number (e.g., V2R2)
in your assessment records.

### 1.2 Identify Systems in Scope

Confirm which systems are within the authorization boundary before scanning. Cross-reference
against the system boundary in the SSP (`SSP-Template.md §2.3`).

| System | Hostname | OS | Last Scan Date | STIG Version (Last) |
|--------|----------|----|----------------|---------------------|
| Domain Controller / Issuing CA | LAB-DC01 | Windows Server 2022 | 2026-05-28 | MS_Windows_Server_2022_STIG-2.3.10 |
| HTTP CRL Server | Pending | Windows Server 2022 / IIS 10.0 | Pending | IIS not deployed in current phase |
| Test Workstation | LAB-WORKSTATION01 | Windows Server 2022 | 2026-05-28 | MS_Windows_Server_2022_STIG-2.3.10 |

### 1.3 Confirm Hardening Scripts Are Current

Check that the hardening scripts in the repository reflect any changes made since the
last assessment. If GPO settings were manually adjusted outside of the scripts, update
the scripts before scanning so the assessment captures the actual production state.

```powershell
# Review recent changes to hardening scripts
git log --oneline -20 -- Automation-Scripts/ Group-Policy/
```

---

## 2. SCAP SCC Delta Scan

### 2.1 Run the Scan

Follow the procedures in `Architecture/FedGov-Tools-Setup-Guide.md §1`.

Key steps:
1. Launch SCAP Compliance Checker (SCC)
2. Import current SCAP 1.3 benchmarks from `FedCompliance-Tools\03-SCAP-Content\`
3. Select all applicable XCCDF profiles for each target OS
4. Run scan against each in-scope system
5. Export results in both HTML and XCCDF XML formats

```powershell
# After scans complete, stage results to the annual archive folder
# Create a dated subfolder under Compliance-Reports
$year = (Get-Date).Year
New-Item -ItemType Directory -Path "Compliance-Reports\Annual-$year" -Force

# Copy from SCC output directory
.\Stage-Reports.ps1   # choose option 2 (After-MFA) to overwrite the current hardened state
```

### 2.2 Compare Against Prior Year

Pull the previous year's XCCDF XML from `Compliance-Reports\After-MFA\` and compare
finding counts. The goal is to show no regression — the post-hardening score should
be equal to or better than the prior year.

| Metric | 2026 Baseline (After-MFA) | Next Year | Delta | Status |
|--------|-----------|-----------|-------|--------|
| DC01 Windows Server 2022 compliance % | 42.66% | [FILL IN] | | |
| WS01 Windows Server 2022 compliance % | 42.20% | [FILL IN] | | |
| CAT I open findings (per VM) | 9 | [FILL IN] | | |
| CAT II open findings (DC01 / WS01) | 110 / 111 | [FILL IN] | | |
| New findings (not in baseline) | — | [FILL IN] | | Investigate |
| Remediated since baseline | — | [FILL IN] | | |

**If compliance dropped or new CAT I findings appeared:** investigate before proceeding.
New findings indicate configuration drift, new STIG rules in an updated benchmark, or
a recent patch that changed a system setting.

### 2.3 STIG Viewer Checklist Update

Open DISA STIG Viewer, load the current STIG XCCDF, and import the new SCAP results.
Review any findings that changed status compared to the prior checklist (.ckl file).

For each new open finding:
1. Determine if it is a true finding or a false positive
2. If true: add to the POA&M (`POAM-Template.md`) with a remediation timeline
3. If false positive: document the Not Applicable rationale in STIG Viewer and save the .ckl

Export updated .ckl files to `Compliance-Reports\After-MFA\` and overwrite the prior year's files.

---

## 3. Nessus Vulnerability Re-Scan

Run a credentialed Nessus Essentials scan following `Architecture/FedGov-Tools-Setup-Guide.md §4`.

Compare the new results against the prior year's PDF report.

| Metric | Prior Year | This Year | Delta |
|--------|-----------|-----------|-------|
| Critical findings | [FILL IN] | [FILL IN] | |
| High findings | [FILL IN] | [FILL IN] | |
| Medium findings | [FILL IN] | [FILL IN] | |

**For any new Critical or High findings:** add to the POA&M with a 30-day remediation target.

Export the Nessus PDF to `Compliance-Reports\After-MFA\Hardened-Vulnerability.pdf` (overwrites prior).

---

## 4. PKI Health Check

Run the PKI health monitor before finalizing the assessment to confirm the PKI
infrastructure is healthy going into the annual review.

```powershell
.\Automation-Scripts\Monitor-PKIHealth.ps1 `
    -CRLUrls @("http://pki.lab.local/crl/RootCA.crl","http://pki.lab.local/crl/IssuingCA.crl") `
    -IssuingCAServer "ca01.lab.local"
```

Confirm:
- [ ] All CRL URLs are reachable and within validity window
- [ ] Issuing CA certificate expires in more than 60 days
- [ ] Root CA CRL expiry is more than 30 days out
- [ ] All enrolled smart card certs for key accounts are current

If the Root CA CRL is within 6 months of expiry, schedule a Root CA signing ceremony
to publish a new CRL before the current one expires. This requires the Offline Root CA
VM and the USB transfer kit from `Download-OfflineCA-Kit.ps1`.

---

## 5. POA&M Update

After scans are complete, update `POAM-Template.md`:

1. Mark any findings remediated since the last assessment as Closed
2. Add any new open findings discovered in this assessment
3. Review risk acceptance entries — confirm they are still valid
4. Update the milestone schedule with new target dates

Summarize the POA&M changes for the AO:
- Findings closed since last assessment: [FILL IN]
- New findings added: [FILL IN]
- Risk acceptances renewed: [FILL IN]
- Outstanding CAT I findings: [FILL IN]

---

## 6. ATO Renewal Documentation

If this assessment is within 90 days of the ATO expiration, package the following
and submit to the Authorizing Official for ATO renewal:

| Document | Location | Status |
|---------|---------|--------|
| Updated SSP | `SSP-Template.md` | [ ] Updated with current scan scores |
| Updated SAR | `SAR-Template.md` | [ ] Updated with this year's findings |
| Updated POA&M | `POAM-Template.md` | [ ] All findings current |
| SCAP SCC results (XCCDF + HTML) | `Compliance-Reports/After-MFA/` | [ ] Current year scan staged |
| STIG Viewer checklists (.ckl) | `Compliance-Reports/After-MFA/` | [ ] Updated |
| Nessus scan PDF | `Compliance-Reports/After-MFA/` | [ ] Current year scan |
| ATO renewal letter | `ATO-Letter-Template.md` | [ ] Prepared for AO signature |

---

## 7. Pre-Push Sanitization

Before committing any scan results or updated documents to the repository:

```powershell
# Preview for real organizational identifiers
.\Scrub-Repo.ps1 -WhatIf

# Apply replacements
.\Scrub-Repo.ps1

# Review the diff
git diff

# Commit
git add Compliance-Reports/ Architecture/
git commit -m "Annual STIG re-assessment — $(Get-Date -Format 'yyyy')"
git push
```

---

## 8. Assessment Record

Fill in after each annual cycle.

| Assessment Year | Assessor | Scan Date | WS2022 Score | CAT I Open | Nessus Crit/High | ATO Status |
|----------------|---------|-----------|-------------|------------|-----------------|------------|
| 2026 | Glenn Byron | 2026-05-28 | DC01: 42.66% / WS01: 42.20% | 9 per VM | Pending (Nessus not run) | ATO with conditions |
| 2027 | [FILL IN] | [FILL IN] | [FILL IN]% | [FILL IN] | [FILL IN] | [FILL IN] |
| 2028 | [FILL IN] | [FILL IN] | [FILL IN]% | [FILL IN] | [FILL IN] | [FILL IN] |

---

*Related: `Architecture/FedGov-Tools-Setup-Guide.md`, `Architecture/STIG-Hardening-Guide.md`,
`POAM-Template.md`, `SAR-Template.md`, `ROADMAP.md Phase 6`.*
