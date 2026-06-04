# Changelog — CAC/PIV ICAM Portfolio

**Author:** Glenn Byron
**Project:** Enterprise ICAM: CAC-Style Identity & Access Deployment Blueprint
**Format:** Chronological by build session, organized by program phase.

This log covers every artifact produced across the life of the project — scripts, architecture documents, compliance templates, lab infrastructure, and DevSecOps controls. Entries show what was built, the NIST control addressed, and the document ID assigned at the time.

---

## [Lab — Session 14] — 2026-06-04

### SCAP Workflow Automation

#### Added

**`Lab-Kit/05-Compliance/Invoke-SCAPWorkflow.ps1`**
Automates the complete SCAP before/after compliance scan loop. Runs SCAP SCC headless against the target, stages XCCDF results to Compliance-Reports\Before-MFA\ or After-MFA\, feeds both files through the scap_summary Docker tool, optionally triggers the Ansible STIG hardening playbook via WSL, and generates a side-by-side delta report (Before-Report.txt → SAR-Template.md). Supports -Phase Before/After/Full, -WhatIf, and -SkipHardening. NIST controls: CA-2 (Security Assessments), RA-5 (Vulnerability Monitoring and Scanning). Author: Glenn Byron.

### PKI Health Baseline + Slot 6 Capture

#### Added

**`Screenshots/06-pki-health-dashboard.png`** + **`Compliance-Reports/PKI-Health/2026-06-04/`**
Real console capture of `Monitor-PKIHealth.ps1` running on Lab-DC01 at 12:18:49 — banner, all five check sections, and the `ALL CHECKS PASSED — PKI environment is healthy.` summary line. Wired into `Demo-Walkthrough.md` Step 6 (slot 6) with honest annotation: rows show `[SKIP]` because optional parameters weren't passed in this baseline run; a follow-up parameterized run is queued for v1.1. Audit-log evidence (`PKIHealth-DC01-AuditLog.txt`) shows seven independent script invocations across the day, all `Critical: False | Warning: False` — immutable CA-7 continuous-monitoring pulse. Folder includes a `README.md` mapping the artifacts to RMF SAR Section 3, POAM baseline-pulse, and SSP Section 7.

### WALKTHROUGH.md Gap Closed — Step 3b (Workstations OU Pre-Domain-Join Scoping)

#### Changed

**`WALKTHROUGH.md`** — added Phase 6 Step 3b
Phase 6 (Domain Controller Setup) jumped from Step 3 (Build-CA-GPO) straight to Step 4 (Install PSPKI), silently skipping the critical pre-domain-join action: create the Workstations OU, `redircmp` it as the default computer container, and scope `scforceoption=1` GPO to that OU only. Without this step, the smart card enforcement GPO defaults to the domain root and locks out Lab-DC01 on the next `gpupdate` — the most common catastrophic failure mode in the build. The recovery is documented in `Lab-Kit/Reference/TROUBLESHOOTING.md`; the prevention now lives in WALKTHROUGH at the correct sequence point. Sourced from the 2026-05-26 lab export `CAC-Lab-Kit-20260526-lab-file.zip`. Section includes a built-in safety check that auto-removes any accidental domain-root link before exit.

Other WALKTHROUGH.md sections found only in the lab export — "IP Reference" table, "Passwords" table, "Break-Glass Accounts" reference block — intentionally not merged. The IP Reference is already covered in `Lab-Kit/Reference/ONBOARDING.md` and `Lab-Kit/START-HERE.md`. The Passwords table conflicts with the repo's placeholder-everywhere convention (`<LAB-ADMIN-PASSWORD>` inline rather than a credentials table). The Break-Glass Accounts content lives more naturally in `Lab-Kit/Reference/TROUBLESHOOTING.md` next to the symptom it recovers from — which already documents the per-user (`SmartcardLogonRequired`) vs machine-wide (`scforceoption`) distinction.

### Live-Servers + Tools-Kit Sync from Lab Export

**Trigger:** Reviewed `CAC-Lab-Kit-20260526-lab-file.zip` (lab snapshot, 105 MB, 182 files) and identified two folders present on the lab DC but missing from the public repo. Both folders are clean of sensitive patterns (audited against every entry in `.scrub-patterns.local.json` — lab passwords, real organizational identifiers, real-world subnets, real email, labtech cert thumbprint — zero hits across all 11 files). Imported as-is, no scrubbing required.

#### Added

**`Live-Servers/`** (new top-level folder, 5 files)
Production deployment helpers — the bridge from the Hyper-V test lab to real production servers. `Test-ServerReadiness.ps1` is a read-only assessor that reports what is installed, what is missing, and the exact command to fix each gap on any target server. `Test-GPOCompliance.ps1` takes a GPO name and verifies (1) it is linked, (2) it has applied to the machine, and (3) the registered settings are active in the registry — with built-in profiles for smart card, audit policy, and VPN GPOs. Supporting docs: `Install-Guide.md` (step-by-step install organized by server role and phase), `GPO-Check-Guide.md` (how to read the compliance output), `README.md` (folder index). Closes the design-it-in-lab / validate-on-target loop with the same tooling. Author: Glenn Byron.

**`Tools-Kit/`** (new top-level folder, 6 files)
Bootstrap downloader for the compliance and PKI tools the lab depends on. `Get-LabTools.ps1` is the one-command entry — run on any internet-connected machine, it stages `C:\FedCompliance-Tools\` ready to copy onto lab VMs (also supports `-OutputPath` to stage directly to a USB drive). Category-specific bundles in `Download-FedCompliance-Kit.ps1`, `Download-IssuingCA-Kit.ps1`, `Download-OfflineCA-Kit.ps1`. `Manual-Downloads/SCAP-SCC-Instructions.txt` covers the few items that require a manual click (public.cyber.mil login). `START-HERE.md` is the folder index. Improves portfolio reproducibility — anyone cloning the repo can bootstrap the same tools used to build the lab. Author: Glenn Byron.

#### Removed

**`TROUBLESHOOTING.md`** (top-level, stale 12.7 KB copy)
Removed in favor of the canonical `Lab-Kit/Reference/TROUBLESHOOTING.md` (21.6 KB, sanitized). The top-level file was a strict subset that predated the Reference/ sync — missing the Common Lab Operations section (at the top) and the entire Physical Endpoint / Smart Card Enrollment section (six entries including the certreq enrollment-target-store gotcha and the TightVNC PIN-blocking issue). `README.md` updated to point at the Reference/ location with descriptive link text.

### Real-World Deployment Bug Fixes (Phase 8 + PKI Monitor)

**Trigger:** Running `Monitor-PKIHealth.ps1` and `Set-AuthenticationPolicySilo.ps1` on Lab-DC01 surfaced two real PowerShell 5.1 / Active Directory edge cases that didn't show up in -WhatIf testing. Both fixes are battle-tested by actual lab deployment.

#### Changed

**`Lab-Kit/07-ZeroTrust/Set-AuthenticationPolicySilo.ps1`** — `Grant-ADAuthenticationPolicySiloAccess` rejects group objects
Symptom: `Cannot find an object with identity: 'Tier-0-Admins' under: 'DC=lab,DC=local'`. Root cause: `Grant-ADAuthenticationPolicySiloAccess -Account` only accepts individual user/computer accounts; passing a security group (`Tier-N-Admins`) throws a terminating `ADIdentityNotFoundException` that bypasses `-ErrorAction SilentlyContinue`. Secondary issue: steps 3-4 (grant + bind) executed even when the silo hadn't been created yet in `-WhatIf` mode. Fix: moved `Grant-ADAuthenticationPolicySiloAccess` into a per-member loop, each user/computer account granted individually; added `$siloExists` guard so steps 3-4 skip when the silo is absent (including dry-run); wrapped each AD call in try/catch so the loop continues on per-account failures; added inline note that the script must be re-run after populating admin groups to bind newly added accounts. NIST controls affected: AC-3, AC-3(7), AC-6, IA-2.

**`Lab-Kit/03-DomainController/Monitor-PKIHealth.ps1`** — `Write-HealthSummary` crashes on `.Count` under StrictMode
Symptom: `The property 'Count' cannot be found on this object. Verify that the property exists.` at line 464. Root cause: in PowerShell 5.1, when a pipeline produces zero output (e.g. `Where-Object` filtering an empty array), the result is `[AutomationNull]` — an internal type that isn't a real array. Under `Set-StrictMode -Version Latest`, accessing `.Count` on `AutomationNull` throws `PropertyNotFoundException` even when the expression is wrapped in `@()`. Fix: replaced the `Where-Object` + `.Count` pattern in `Write-HealthSummary` with a `foreach` loop using plain integer counters (`$critCount`, `$warnCount`) and `[System.Collections.ArrayList]` collectors — integer variables always support `-eq 0` cleanly. Added `if ($script:findings)` null guards in `Write-HealthSummary` and `Send-AlertEmail` to prevent the same class of error if `$script:findings` is ever `$null` rather than `@()`. NIST controls affected: CA-7 (Continuous Monitoring), SC-17 (PKI Certificates).

---

## [Lab — Session 13] — 2026-06-02

### Sync from Lab-Export, Subnet Drift Fix, First Real Screenshots

**Trigger:** Glenn provided `CAC-Lab-Export-20260602.zip` from the Hyper-V host containing the latest lab state — physical laptop WO02 domain-joined with `LAB\labtech` enrolled (VSC, PIN 123456, cert valid 6/2/26→6/2/27), smart card logon **CONFIRMED PASS** via RDP to 10.10.20.30. Network topology changed during the laptop add: DC01 now dual-NIC (`10.10.10.10` LabInternal + `10.10.20.10` External); WS01 stays on `10.10.10.20`. The After-MFA SCAP scans (May 28) recorded: DC01 42.66% / WS01 42.20%.

#### Added

**`Screenshots/`** (new folder, 5 files)
First real lab captures committed to the repo. Four PNGs from Glenn's lab work (Lab-WS01 PIN entry, Lab-WS01 incorrect-PIN dialog, enrollment ceremony Issuer-phase success on DC01, pre-Kerberos-cert troubleshooting failure on WO02). One slot in `Demo-Walkthrough.md` (Step 2 PIN entry) now has a real image; the other 8 slots remain pending with explicit "Pending capture - see Screenshots/README.md" markers. `Screenshots/README.md` lists what's captured, what's still pending, capture guidelines (PNG over JPG, sanitize names/hostnames/IPs outside `10.10.10.x`/`10.10.20.x`), and the naming convention (`NN-description.png` matching slot number, `evidence-` prefix for portfolio-only shots, `troubleshoot-` prefix for problem/fix references).

**`Lab-Kit/Reference/ONBOARDING.md`** (21 KB, scrubbed)
Synced from the lab export. Quick-start guide for new users, new machines, and day-one lab orientation. Covers: VM inventory with dual-NIC IPs, host adapter table, lab accounts (Administrator / CardIssuer / labtech / local), domain join steps, user creation, complete smart card enrollment in 7 parts (one-time prereqs, create user, RA ceremony, machine setup with VSC vs. physical card paths, certificate enrollment as target user, Issuer ceremony as CardIssuer, cleanup and enforcement re-enable, RDP test), zero-trust temporary local-admin pattern, checkpoint commands. Real passwords scrubbed to `<LAB-ADMIN-PASSWORD>` and `<LAB-LABTECH-PASSWORD>`. Cert thumbprint scrubbed to `<LABTECH-CERT-THUMBPRINT>`.

**`Lab-Kit/Reference/TROUBLESHOOTING.md`** (22 KB, scrubbed)
Synced from the lab export. Running FAQ of every real problem encountered in the lab. Sections: Smart Card / Authentication, Group Policy, Active Directory & Domain, SYSVOL & GPO Infrastructure, Workstation Domain Join, SCAP / Compliance Checker, General Windows / PowerShell, Common Lab Operations, Physical Endpoint / Smart Card Enrollment. Same scrubbing as ONBOARDING.

#### Changed

**`Demo-Walkthrough.md`**
Replaced the seven `📸 Screenshot slot` placeholders with status markers. Slot 2 (PIN entry) now embeds two real images: `Screenshots/02-pin-entry-cert-subject.png` and `Screenshots/02b-incorrect-pin-validation.png` (supplement proving PIN validation works). Slots 1, 3, 4, 5, 6, 7 show `📸 Pending capture` markers pointing to `Screenshots/README.md` for the capture checklist. Slot 7 (SCAP delta) annotated with the real before/after numbers (DC01 44.95%→42.66%, WS01 42.20%→42.20%).

**`Lab-Kit/LAB-BUILD-CHANGELOG.md`** (37 KB → 50 KB, scrubbed)
Overwritten with the latest export version. Adds Session 4 (2026-06-01) entries for WS01 domain rejoin with NetBIOS name truncation lesson learned (`Lab-Workstation01` → `LAB-WORKSTATION`), SmartCard Policy GPO with scforceoption=1 added now that WS01 is in Workstations OU, After-MFA SCAP scans completed (DC01 42.66%, WS01 42.2%), and the 05-After-Scan checkpoint. Adds Session 4 continued (2026-06-02) entries for WO02 domain join + smart card enrollment complete, dual-NIC DC01 topology change with 10.10.20.x subnet for External, DC01 KerberosAuthentication cert enrollment fix, SmartcardLogon template Enroll permission fix using AD extended rights GUID directly (PSPKI was silently dropping Enroll), labtech user creation, and 8 lessons learned. Same scrubbing.

**`TODO.md`** — Portfolio Finalization section
Marked screenshot line as in-progress (⏳): 1 of 9 captured, 8 pending. Lists exactly which slots are filled (Step 2 PIN entry) and which still need capture (lock screen, Event 4768, session lock, VPN, PKI dashboard, SCAP delta, Win11 STIG result on WO02).

**`.scrub-patterns.example.json`**
Added a second `_README_LAB_SECRETS` comment block explaining the placeholder convention used by the new `Lab-Kit/Reference/` docs. Added three commented-shape example keys (`your-real-lab-admin-password`, `your-real-lab-labtech-password`, `your-real-cert-thumbprint-40-hex-chars`) so users know to put their real values in `.scrub-patterns.local.json` and have them swapped for the placeholders during `Scrub-Repo.ps1` runs.

**`Lab-Kit/01-HyperV-Host/Export-LabVMs.ps1`** (336 lines)
New PowerShell script that produces a portable export of the lab VMs for backup, disaster recovery, or reuse as a Home-Lab foundation. Defaults: exports `Lab-DC01` and `Lab-OfflineRootCA` to `D:\VM-Exports\LabExport-<yyyyMMdd-HHmm>\`, gracefully shuts down running VMs first (clean state, avoids USN rollback for the DC), strips checkpoints for a clean single-state export, restarts the VMs after export, drops an `EXPORT-MANIFEST.md` describing what's inside and how to restore. Validates target drive has enough free space (sum of VM sizes + 10% headroom) before starting. Switches: `-IncludeWorkstation` (adds WS01), `-IncludeCheckpoints` (preserves snapshots), `-SkipShutdown` (live/saved-state export, warns), `-LeaveVMsOff` (skip auto-restart), `-SkipDriveCheck`. Uses `[CmdletBinding(SupportsShouldProcess)]` and respects `-WhatIf`. Author: Glenn Byron.

**`Lab-Kit/01-HyperV-Host/Get-LabVMSize.ps1`** (320 lines, read-only planner)
Non-destructive planning helper that reports current VM disk usage and estimates the resulting export size BEFORE running Export-LabVMs.ps1. Per VM it shows: state (Running/Off/Saved), processor count, memory, count and total size of attached VHDX disks, count and accumulated size of snapshot `.avhdx` differencing disks, and full folder footprint. Estimates two export modes: clean single-state (parent VHDX only, snapshots merged away) and with-checkpoints (full folder). Surveys free space on `-TargetDrives` (default `D:`) and gives a green/red go/no-go assessment with a 10% headroom buffer. Final recommendation block emits the exact `Export-LabVMs.ps1` command to run, parameterized to the drive with the most headroom. Optional `-ReportPath` writes a markdown report alongside the screen output for archival. Author: Glenn Byron.

**`Lab-Kit/01-HyperV-Host/Import-LabVM.ps1`** (235 lines)
Companion to Export-LabVMs.ps1. Wraps `Import-VM` with two modes: Copy (default, files go to `-DestinationPath`, original export preserved for next import) and Register (export folder becomes the live VM location, single use). Supports `-NewName` for renaming on import (lets multiple imported copies coexist) and `-VMSwitch` for reconnecting network adapters when destination host has different switch names than source. Uses `Compare-VM` to preview the imported VM's hardware spec and surface compatibility issues before committing. Warns the user that the imported VM keeps its original domain SID and must not run alongside the original (duplicate-SID Kerberos breakage), with a pointer to `VM-Reuse-Workflow.md` for the demote/re-promote pattern when an independent clone is needed. Switches: `-RegisterInPlace`, `-Force` (overwrite existing same-named VM after Stop+Remove). Author: Glenn Byron.

**`Compliance-Reports/Laptop/After-SmartCard/2026-06-02_104513/`** (new SCC session, 10 files, 8.5 MB)
First STIG SCAP scan of the WO02 physical laptop, run today at 10:45:13 against `Microsoft_Windows_11_STIG-2.3.9` (MAC-1 Classified profile, the highest-rigor DISA STIG profile available). **WO02 scored 37.00%** compliance: 258 rules total, 84 pass, 143 fail, 31 not-checked (manual questions deferred to STIG Viewer review), 0 errors. CAT-severity breakdown: **13 CAT I open**, **122 CAT II open**, **8 CAT III open**. Complete SCC session preserved — Summary Viewer HTML, full per-setting HTML, non-compliance HTML, STIG Viewer .ckl checklist, XCCDF/OVAL/OCIL XML, scan error log. `Compliance-Reports/README.md` updated with the new scoring row, the Windows 11 STIG benchmark callout (different benchmark from DC01/WS01), and an interpretation paragraph explaining why a single-stage After-SmartCard scan is acceptable evidence for the laptop. `Compliance-Reports/Laptop/Before-SmartCard/.placeholder` documents the deliberate absence of a baseline scan and the rationale (WS01 Before-MFA serves as the equivalent baseline-Windows reference). TODO.md Windows 11 STIG line marked ✅. `Demo-Walkthrough.md` Step 7 SCAP-delta annotation updated with all three hosts' real numbers (DC01 44.95→42.66, WS01 42.20→42.20, WO02 37.00 single-stage). Author: Glenn Byron.

**Subnet drift fix** — 192.168.1.x → 10.10.10.x / 10.10.20.x across the following files in the CAC-program repo:
- `Lab-Kit/06-PhysicalEndpoint/Add-Physical-Laptop.md` — Step 1 New-NetIPAddress, DNS instructions, ping/nslookup verification, troubleshooting note. Added a callout block listing the real LabInternal vs. External subnet split with a pointer to ONBOARDING.md.
- `Lab-Kit/Ansible/inventory.ini.example` — `dc01` 192.168.1.10→10.10.10.10, `member01` →10.10.10.11, `ws01` →10.10.10.20, added `wo02 ansible_host=10.10.20.30` on the External subnet. Added a comment block explaining the dual-subnet plan.
- `Lab-Kit/Physical-Lab-Setup.md` — iDRAC IP example (now uses 10.10.10.50 range), SSH example (10.10.10.50).

Author: Glenn Byron.

---

## [Lab — Session 12] — 2026-06-01

### Physical Laptop Pre-Flight — Hardware Confirmed + USB Staging Script

#### Added

**`Lab-Kit/06-PhysicalEndpoint/Stage-LaptopUSB.ps1`** (325 lines)
New PowerShell script that bundles every file the physical laptop needs into a single timestamped staging folder on the Hyper-V host, ready to drag onto a USB drive. Stages five items: (1) SCC 5.10.2 installer from `FedCompliance-Tools\00-SCAP-SCC\`; (2) Windows 11 STIG SCAP content from `FedCompliance-Tools\03-SCAP-Content\` (filters to Windows 11 benchmark files only, ignores Server 2022); (3) Lab Root CA public certificate (optional `-RootCACertPath`, refuses `.pfx`/`.p12` to keep the private key offline); (4) `Add-Physical-Laptop.md` walkthrough; (5) `Deploy-VPNClient.ps1` for the VPN step. Auto-generates a `README.txt` on the USB root that lists contents with [OK]/[MISSING] markers, the Step 0–7 walkthrough order, and Root CA export instructions if the cert was not staged. Optional `-Zip` switch produces a single archive; `-Force` overwrites prior staging folders. Missing items are warnings (not failures) so the operator sees what still needs sourcing. NIST controls supported: CM-7 (least functionality, no private keys exfiltrated), MP-5 (media transport), AC-19 (mobile device access). Author: Glenn Byron.

#### Changed

**`TODO.md`**
Marked Windows 11 and TPM 2.0 prerequisites complete in the Physical Laptop section. Both boxes confirmed via `winver` (Windows 11 Pro) and `tpm.msc` (TPM 2.0 ready) on the spare laptop. Outstanding laptop tasks: External vSwitch creation, domain-join, smart card GPO application, VSC creation, cert enrollment, smart card logon test (screenshots), Windows 11 STIG SCAP scan, VPN test. Author: Glenn Byron.

**`TODO.md` line 100 + `Lab-Kit/06-PhysicalEndpoint/Add-Physical-Laptop.md` Step 6**
Updated SCAP benchmark label from bare `MS_Windows_11_STIG` to versioned form `MS_Windows_11_STIG-<version>` with the note that the current DISA release is V1R7+. This aligns Windows 11 references with the version-suffix convention already used elsewhere in the repo for the Server 2022 benchmark (e.g. `MS_Windows_Server_2022_STIG-2.3.10`). Author: Glenn Byron.

**`Pack-LabKit.ps1`**
Three fixes after first packaging run leaked IDE config into the distribution zip: (1) re-encoded the file as UTF-8 with BOM and replaced em dashes / box-drawing characters with ASCII equivalents so PowerShell 5.1 parses it correctly without ANSI mis-decoding; (2) restored a truncated final `Write-Host` call (file had ended mid-token with literal `Wri`); (3) added `.idea`, `.vs`, `.vscode`, and `node_modules` to the `$excludeDirs` list so IDE-local folders (already in `.gitignore` but still in the working tree) are excluded from the packaged zip. First clean run packaged 116 files → 3.3 MB zip (78% compression); expected to drop to ~108 files after the IDE exclusion fix. Author: Glenn Byron.

---

## [Portfolio — Session 11] — 2026-05-29

### Resume — NAVAIR ESDP Targeted Version

#### Added

**`Portfolio/Glenn_Byron_Resume_V3_ESDP.docx`**
Rebuilt resume targeting NAVAIR ESDP (Engineer and Scientist Development Program) at NAS Patuxent River. Key changes from V2: added professional summary connecting 5+ years of sysadmin experience to DoD ICAM/DevSecOps work; expanded technical skills to include CAC/PIV, PKI/AD CS, Ansible, Docker, GitHub Actions, PowerShell, Python, SCAP/XCCDF, and Zero Trust; added new Projects section showcasing the CAC/PIV ICAM lab, DevSecOps pipeline, STIG hardening automation, and SCAP compliance parser; strengthened Agency cybersecurity bullets to remove "foundational knowledge" language; added CySA+ (in progress, Q3 2026) and AZ-500 (in progress, Q4 2026) to certifications; trimmed AutoZone section. Author: Glenn Byron.

---

## [DevSecOps — Session 10] — 2026-05-29

### CySA+ Study Tool

#### Added

**`Study/CySA-Plus-Study-Tool.html`**
Standalone interactive quiz tool for CySA+ CS0-003 exam preparation. Covers all four exam domains in proportion to their actual weights: Security Operations (33%, 10 questions), Vulnerability Management (30%, 10 questions), Incident Response (20%, 8 questions), and Reporting & Communication (17%, 7 questions). Questions cover topics directly tested on the exam: MITRE ATT&CK, Windows Event IDs, DGA beaconing, CVSS v3 scoring, NIST SP 800-61 incident phases, order of volatility, FAIR risk model, ACAS/Tenable, UEBA, and DoD-specific processes. Fully self-contained single HTML file — no external dependencies, no server required. Features domain filter tabs, live progress bar, per-question explanations, and a scored end screen with pass/near-pass/retry grade (passing threshold ≥83%, matching the real exam). Questions shuffle on each session. Author: Glenn Byron.

---

## [DevSecOps — Session 9] — 2026-05-29

### Career Roadmap Document

#### Added

**`Portfolio/DevSecOps-Career-Roadmap.docx`**
Comprehensive DevSecOps career roadmap document covering: confirmation that DevSecOps roles exist at NAS Patuxent River (NAVAIR, Lighthouse platform, cATO adoption, contractor presence); honest snapshot of current strengths and gaps; phased roadmap (30 days / 90 days / 6 months / 1 year / 2 years); skills priority table with resources; certifications roadmap (CySA+, AZ-500, CASP+, CDP, CKS, CISSP) with DoD 8140 mapping; projects to build next; DoD-specific knowledge (Platform One, Iron Bank, Navy Lighthouse, cATO, NIST SP 800-218, EO 14028, Cloud SRG); companies at Pax River with notes on clearance sponsorship; resume priorities and interview talking points. Author: Glenn Byron.

---

## [DevSecOps — Session 8] — 2026-05-29

### DevSecOps Pipeline — CI/CD Security Scanning and IaC

#### Added

**`.github/workflows/codeql.yml`**
CodeQL SAST (Static Application Security Testing) workflow. Analyzes Python code in the repo on every push and pull request that touches `.py` files, plus a weekly scheduled scan to catch newly disclosed CVEs in unchanged code. Uses the `security-and-quality` query suite — broader than the default, catches injection, insecure crypto, path traversal, and hardcoded credentials. Results upload to GitHub Security → Code scanning alerts as SARIF. Author: Glenn Byron.

**`.github/workflows/trivy.yml`**
Trivy container vulnerability scan workflow. Builds the `scap-summary` Docker image and scans it for CRITICAL and HIGH CVEs on every push that touches `docker/`. Fails the build on unpatched critical/high findings — equivalent to the container gate in a DoD DevSecOps pipeline (Platform One / Iron Bank). Full results including MEDIUM findings upload to GitHub Security tab as SARIF. Includes a daily scheduled scan to catch newly published CVEs in unchanged images. Author: Glenn Byron.

**`.github/workflows/dependency-review.yml`**
Software Composition Analysis (SCA) workflow. Blocks pull requests that introduce Python dependencies with known HIGH or CRITICAL CVEs. Posts a findings summary comment on the PR. Also flags GPL-3.0 and AGPL-3.0 licenses that may conflict with MIT and DoD open-source policy. Implements EO 14028 supply chain security requirements. Author: Glenn Byron.

**`docker/scap-summary/scap_summary.py`**
Python tool that parses DISA SCAP SCC XCCDF results files and produces a plain-language CAT I / CAT II / CAT III compliance summary — the same finding triage a DoD IA technician performs after an ACAS scan. Outputs text report (matching DoD IA reporting style) or JSON. Uses `defusedxml` to prevent XXE attacks (CWE-611) when parsing untrusted XML. Author: Glenn Byron.

**`docker/scap-summary/Dockerfile`**
Multi-stage Dockerfile for the scap-summary tool. Stage 1 (builder) installs dependencies to a separate prefix. Stage 2 (runtime) uses `python:3.12-slim` — minimal attack surface. Runs as a non-root user (UID 1001, no shell) per DISA container STIG requirements. Includes OCI image labels. Scanned by Trivy on every push. Author: Glenn Byron.

**`docker/scap-summary/requirements.txt`**
Python dependencies for scap-summary. Uses `defusedxml` instead of stdlib `xml.etree.ElementTree` — a deliberate security choice documented in the file with the CWE reference.

**`Lab-Kit/Ansible/windows-stig-hardening.yml`**
Ansible playbook automating key DISA STIG controls for Windows Server 2022 lab machines. Covers 8 sections: account lockout policy (WN22-AC-000030/040/050), password policy (WN22-AC-000060–100), audit policy (WN22-AU-000030–120 subset), disabling risky services (Print Spooler, SMBv1, LLMNR, NetBIOS), Windows Firewall enforcement on all profiles, Remote Desktop NLA and encryption requirements, legal notice banner (WN22-SO-000070/080), and User Rights Assignment restrictions (WN22-UR-000010/020). Tagged by section so individual areas can be applied independently. Prints an auditable summary at the end of every run. NIST control mapping: AC-2, AC-6, AC-7, AC-8, AC-17, AU-2, AU-12, CM-7, IA-2, IA-5, SC-7. Author: Glenn Byron.

**`Lab-Kit/Ansible/inventory.ini.example`**
Ansible inventory template with lab machine roles (lab\_servers, lab\_workstations), WinRM connection variables, and comments explaining the lab vs. production security difference (HTTP basic auth in lab, Kerberos + HTTPS in production). The real `inventory.ini` is gitignored — credentials never committed.

**`Lab-Kit/Ansible/README.md`**
Setup and usage guide for the Ansible playbook: prerequisites (pywinrm, ansible.windows collection), WinRM setup on Windows targets, dry-run and apply commands, tag reference, and lab vs. production caveats.

#### Changed

**`TODO.md`**
Added DevSecOps section with pipeline and Ansible tasks.

---

## [Physical Lab — Session 7] — 2026-05-29

### Physical Hardware Path — Dell Lab Setup Guide

#### Added

**`Lab-Kit/Physical-Lab-Setup.md`**
Comprehensive guide for building the CAC/PIV lab on real Dell hardware instead of Hyper-V VMs. Includes four topology options: Option A (all physical); Option B (hybrid — VM DC on laptop + physical machines on switch); Option C (all infrastructure on laptop VMs, physical clients on switch); Option D (everything on laptop VMs — Offline Root CA isolated with a Hyper-V Private vSwitch, file transfer via PowerShell Direct). Includes interviewer talking points for explaining the VM air-gap simulation and VM resource requirements table for Option D. Covers: pre-wipe hardware checklist (service tag lookup, iDRAC version identification, TPM verification, RAM/storage minimums); iDRAC initial configuration (static IP, default password change, firmware update, virtual console and virtual media setup, RACADM CLI overview); recommended machine role assignment (Offline Root CA air-gapped, DC01 + Issuing CA, MEMBER01 test server, WORKSTATION01 for CAC logon testing); managed switch and VLAN layout (Management, Lab-LAN, OT-Sim, Quarantine); Server 2022 vs. Server 2025 comparison; iDRAC STIG compliance notes (V-225472 through V-225496); Dell OpenManage installation; day-one checklist; and a portfolio skills table showing what physical hardware work demonstrates to a DoD hiring manager. Author: Glenn Byron.

#### Changed

**`TODO.md`**
Added Physical Lab Setup section with hardware checklist items and pointer to the new guide. Updated Last Updated date.

---

## [Phase 8 — Session 6] — 2026-05-29

### Zero Trust Extension — Design & Documentation

#### Added

**`Zero-Trust/Paper-1-Foundations.md`**
Zero Trust foundations paper — the shift from implicit perimeter trust to "never trust, always verify," the PEP/PDP/subject/resource model, the seven NIST SP 800-207 tenets, and the DoD and CISA pillar frameworks. Written as a plain-language reference for practitioners entering DoD IT environments.

**`Zero-Trust/Paper-2-Technical-Deep-Dive.md`**
Technical deep dive on the NIST logical components (Policy Engine, Policy Administrator, Policy Enforcement Point), the trust algorithm (criteria-based vs. score-based, singular vs. contextual), deployment models, identity as the new perimeter, microsegmentation and east-west traffic, workload identity (mTLS/SPIFFE), and the CISA maturity stages.

**`Zero-Trust/Paper-3-Implementation-Checklist.md`**
Actionable implementation checklist organized by the eight ZT areas (Foundation, Identity, Devices, Networks, Applications & Workloads, Data, Visibility & Analytics, Automation, Governance) with items ascending from Initial to Optimal maturity within each section.

**`Zero-Trust/Paper-4-Detailed-Guidance.md`**
Expanded guidance for each checklist area — why it matters, how to implement it, common pitfalls, and what "good" looks like at each CISA maturity stage.

**`Zero-Trust/References.md`**
Authoritative sources behind the paper series: NIST SP 800-207, NIST SP 800-53 Rev. 5, NIST CSF 2.0, NIST SP 1800-35, DoD Zero Trust Strategy, DoD ZT Reference Architecture v2.0, DoD ZT Capability Execution Roadmap, CISA ZTMM v2.0, EO 14028, OMB M-22-09, Maryland Chapter 495 (SB 871 / HB 1062), and the Maryland Cybersecurity and Privacy Policy Suite.

**`Zero-Trust/CAC-Program-ZeroTrust-Gap-Analysis.md`**
Gap analysis of the CAC/PIV program against full Zero Trust requirements. Documents what the program already satisfies (phishing-resistant MFA, air-gapped root CA, SOD enrollment, OCSP/CRL validation, PKI health monitoring, RMF governance) and what to add (authorization/least privilege, device trust, continuous/conditional access, workload identity, microsegmentation, analytics → decisioning). Includes CISA maturity snapshot per pillar and two technical nuances (authentication ≠ authorization; Kerberos ticket persistence).

**`Zero-Trust/diagrams/ZT-Top-Down-Model.svg`**
SVG diagram illustrating the Zero Trust top-down protection model: Governance → Policy Decision Point → Policy Enforcement Point → Pillars → Data, with authority/policy flowing downward and signals/telemetry flowing upward. Dark-themed, suitable for portfolio and presentation use.

**`Zero-Trust/diagrams/ZT-Breach-Cascade.svg`**
SVG diagram showing what happens without Zero Trust — the five-step attack cascade (Initial Access → Implicit Trust → Lateral Movement → Privilege Escalation → Impact) with a gradient attack-path chain, a blast-radius section covering six consequence cards (mission disruption, CUI breach, financial loss, regulatory exposure, ATO loss, reputation damage), and a Zero Trust contrast box at the bottom. Dark-themed, portfolio and presentation ready. Author: Glenn Byron.

**`Portfolio/Zero-Trust-Reference.docx`**
Professional Word document consolidating the Zero Trust paper series and CAC program gap analysis. Covers foundations, technical architecture (PEP/PDP/PE/PA), implementation guidance, gap analysis with CISA maturity snapshot table, and authoritative references. Navy/teal/grey color scheme, Arial font. Suitable for portfolio submission and recruiter review.

**`Lab-Kit/Phase-8-Zero-Trust-Extension.md`**
Design document for Phase 8 — extends the CAC/PIV lab from strong authentication to end-to-end Zero Trust. Seven sub-phases (8.1–8.7) covering authorization and least privilege, device trust, continuous and conditional access, workload/non-person identity, network segmentation and per-app access, visibility and analytics feeding decisioning, and validation and evidence. Each sub-phase lists the planned scripts in Verb-Noun convention, maps to gaps A–G from the gap analysis, and cites the matching NIST SP 800-53 control families. Scripts are the next build phase pending Phase 4 lab execution.

#### Changed

**`TODO.md`**
Added Phase 8 section with all 7 sub-phases, all planned scripts as checkboxes, and updated the status table at the bottom to include Phase 8 row.

**`.gitignore`**
Added `Dispatch/` to gitignore with explanatory comment — the local staging folder is now permanently excluded from all commits and pushes.

**`Dispatch/DISPATCH-LOG.md`** (local only — not in git)
Created the Dispatch session log. Tracks every file in the Dispatch folder, its status (draft/ready to move/private), and a running session log so future sessions can pick up where they left off.

**`Dispatch/README-DoD-draft.md`** (local only — not in git)
DoD/Pax River–targeted README draft. Leads with what the project demonstrates for NAVAIR, defense contractor, and DoD IT hiring managers. Includes a "Why this matters for DoD and defense IT" section, expanded NIST control table, commercial vs. federal PIV comparison table, honest Zero Trust maturity table, and Phase 8 roadmap reference.

---

## [Phase 6 — Session 5] — 2026-05-24

### Documentation Cleanup & Housekeeping

#### Added

**`CHANGELOG.md`** (this file)
Chronological record of every artifact produced across all build sessions, organized by program phase. Each entry describes what was built, which NIST control it addresses, and the document ID assigned at time of creation. Artifact ID reference table at the bottom cross-references all ARCH-ICAM and SCRIPT-ICAM numbers to their file paths.

**`TODO.md`**
Living task list consolidating all remaining work across the project. Organized into four sections: immediate pre-push steps (commit, scrub, push, CI badge check), one-time setup (scrub patterns, GitHub topics), Phase 4 lab execution (VM setup through demo screenshots — every checkbox in sequence), and Phase 5/7 items blocked on lab data. Replaces and supersedes the `.idea/CAC-Program-ToDo.md` scratchpad, which remains gitignored.

#### Changed

**`TODO.md`**
Living task list consolidating all remaining work across the project. Organized into four sections: immediate pre-push steps (commit, scrub, push, CI badge check), one-time setup (scrub patterns, GitHub topics), Phase 4 lab execution (VM setup through demo screenshots — every checkbox in sequence), and Phase 5/7 items blocked on lab data. Replaces and supersedes the `.idea/CAC-Program-ToDo.md` scratchpad, which remains gitignored.

#### Changed

**`Lab-Kit/01-HyperV-Host/New-LabVMs.ps1`**
Added three preflight checks that run before any VM work begins: (1) confirms the script is running as Administrator; (2) checks for the Hyper-V PowerShell module (`Get-VM`) and prints all three ways to enable Hyper-V — `Enable-WindowsOptionalFeature`, Windows Features UI, and Server Manager — plus a note about requiring VT-x/AMD-V in BIOS/UEFI; (3) checks that the Hyper-V Virtual Machine Management service (`vmms`) is in a Running state, catching the case where the feature is installed but the hypervisor is not yet active.

**`Lab-Kit/04-Workstation/README.md`**
Complete rewrite. The previous version was mislabeled as a "Group Policy Configuration Matrices" document. The new version covers: the two scripts in the folder and what each does; smart card reader drivers (CCID readers are plug-and-play on Windows — no extra driver needed); middleware by token type (CardLogix GIDS and YubiKey PIV use the Windows built-in minidriver — no ActivClient required; DoD CAC requires ActivClient or OpenSC); verification steps using `Invoke-LabValidation.ps1`; the GPO settings table with NIST control mapping; and the full workstation setup run order pointing to `Demo-Walkthrough.md` for the demo sequence.

**`Lab-Kit/02-OfflineRootCA/README.md`**
Complete rewrite. The previous version stated "there is no auto-build script here by design" — which was accurate before `Initialize-OfflineRootCA.ps1` was written but would cause anyone reading it to skip the script entirely. The new version describes the script, documents the PowerShell Direct transfer sequence for getting the script and prerequisite tools onto the air-gapped VM, walks through what the 8-step ceremony does, provides the post-ceremony commands for publishing the Root CA cert and CRL on Lab-DC01, and explains why the Root CA stays offline after the ceremony.

**`Lab-Kit/01-HyperV-Host/README.md`**
Fixed Step 5 (now Step 6): updated all `Automation-Scripts\` paths to current `Lab-Kit\03-DomainController\` and `Lab-Kit\04-Workstation\` locations; replaced the manual reference to `Download-OfflineCA-Kit.ps1` with `Initialize-OfflineRootCA.ps1`. Added a new Step 5 covering `New-LabSnapshot.ps1` with the full recommended label sequence (00-BaseOS through 06-Validated) and when to take each checkpoint.

**`Lab-Kit/03-DomainController/README.md`** (new)
Quick-reference README for the busiest folder in the kit. Documents all 9 scripts in run order with a one-line description and NIST control for each, a prerequisite section (static IP, Administrator rights, PSPKI module), key parameter examples for `Build-CAC-Lab.ps1`, `New-TokenEnrollment.ps1`, `New-YubiKeyToken.ps1`, and `Monitor-PKIHealth.ps1`, and a related-docs footer.

**`Lab-Kit/05-Compliance/README.md`** (new)
README for the compliance folder covering both scripts. Documents all 7 validation layers for `Invoke-LabValidation.ps1` in a table, the full parameter set with an example command, and the role of `-ExportReport` in the evidence package. Covers `Stage-Reports.ps1` usage and includes a numbered recommended sequence tying both scripts into the before/after scan workflow.

**`Lab-Kit/START-HERE.md`** (bug fix)
Corrected a path error where `Download-IssuingCA-Kit.ps1` and `Download-FedCompliance-Kit.ps1` were listed under the `03-DomainController` run section — those scripts live in `Tools-Kit\`, not on the DC. Added a new "On Your Hyper-V Host" section before the DC section showing the correct tool-download sequence and PowerShell Direct transfer step.

**`Lab-Kit/03-DomainController/README.md`** (bug fix)
Fixed broken footer link: `Architecture/PKI-Blueprint.md` → `Architecture/Blueprint.md` (the actual filename).

**`Portfolio/CAC-PIV-How-It-Works.docx`**
Plain-language Word document explaining how the CAC/PIV system works in production — written for non-technical audiences, hiring managers, and AO briefings. Six numbered sections: (1) the trust chain is built once then runs itself; (2) getting a user onto the system (identity verification, cert issuance, YubiKey provisioning); (3) every login from that point forward (Kerberos Pre-Auth Type 16, domain controller validation flow); (4) VPN uses the same certificate handshake (IKEv2/EAP-TLS, no password prompt); (5) what keeps it healthy day to day (CRL/OCSP, PKI health monitor, WEF log forwarding); (6) the only time the Root CA is ever needed again (renewal, five-year cycle). Professional formatting: navy blue title and section headings, 11 pt body, 1.15 line spacing, rule lines, italic footer pointing to Demo-Walkthrough.md and START-HERE.md.

**`Lab-Kit/START-HERE.md`**
Added four scripts that were missing from the run-order section: `New-LabSnapshot.ps1` (Hyper-V Host section), `Initialize-OfflineRootCA.ps1` (OfflineRootCA section, sequenced after `Download-OfflineCA-Kit.ps1`), `New-YubiKeyToken.ps1` (Domain Controller section), and `Invoke-LabValidation.ps1` (Compliance section, with a note that it runs before scanning).

**`Lab-Kit/LAB-DAY-CHECKLIST.md`**
Fixed all script paths that still pointed to the old `.\Automation-Scripts\` folder structure. Updated to current locations under `Lab-Kit\03-DomainController\`, `Lab-Kit\04-Workstation\`, `Lab-Kit\05-Compliance\`, and `Tools-Kit\`. Added a Pre-Scan Validation section using `Invoke-LabValidation.ps1` before Phase 4.1. Added checkpoint step in "Before You Start" using `New-LabSnapshot.ps1`. Added a YubiKey provisioning sub-section in Phase 4.4 using `New-YubiKeyToken.ps1`. Updated RMF template paths to include the `RMF-Templates\` subfolder. Added a checkpoint step at the hardening boundary.

**`README.md`**
Replaced the stale Lab Demonstration Walkthrough section (46 lines of `[screenshot]` placeholders) with a short paragraph pointing to `Demo-Walkthrough.md` (DEMO-ICAM-001), which supersedes it with a complete, structured guide.

---

## [Phase 6 — Session 4] — 2026-05-23

### Advanced Automation & Monitoring — Final Items

#### Added

**`Lab-Kit/02-OfflineRootCA/Initialize-OfflineRootCA.ps1`**
8-step guided ceremony for the air-gapped Offline Root CA. Enforces air-gap by checking for active network adapters and requiring "OVERRIDE" to proceed. Generates CAPolicy.inf from an embedded template if not present, installs the AD CS role, configures a StandaloneRootCA (4096-bit RSA, SHA-256, 10-year validity), sets CDP and AIA URLs, publishes the CRL, exports the CA certificate and CRL to a staging folder, and prints the exact PowerShell Direct commands for transferring files to the domain controller. Self-contained for use without internet access. Addresses NIST IA-5(2), SC-17.

**`Lab-Kit/01-HyperV-Host/New-LabSnapshot.ps1`**
Hyper-V checkpoint manager with five modes: Create, List, Restore, Delete, Cleanup. Stamps checkpoint names with a timestamp prefix (`yyyyMMdd-HHmm-Label`) so multiple checkpoints with the same label coexist without collision. Create warns when the VM is running and falls back to Production Checkpoint. Restore requires typing "RESTORE" as a confirmation guard. Cleanup keeps the N most recent checkpoints (default 5) and removes the rest. Comes with a recommended label sequence that matches the lab build stages: 00-BaseOS through 06-Validated.

**`Lab-Kit/05-Compliance/Invoke-LabValidation.ps1`**
Seven-layer pass/fail validation script intended to run before any SCAP SCC scan. Layers: (1) Domain and Network — domain membership, LDAP TCP, DNS, Kerberos time skew; (2) PKI — Root CA and Issuing CA certificate stores, expiry, smart card logon EKU check, CRL download and parse via certutil, OCSP reachability; (3) Smart Card — SCardSvr service, SmartCard device enumerator, reader presence via WMI; (4) GPO — scforceoption=1, ScRemoveOption, InactivityTimeoutSecs; (5) Audit — auditpol subcategories, Security log minimum size; (6) VPN — IKEv2 tunnel type, EAP auth method, AES-256 IPsec policy, optional live connect test; (7) Events — Event IDs 4624 and 4768 in the last 24 hours. Exports a timestamped text report. Addresses NIST CA-7, CM-6.

**`.github/workflows/ps-lint.yml`**
PSScriptAnalyzer GitHub Actions workflow. Runs on every push and pull request touching `.ps1`, `.psm1`, or `.psd1` files. Separates rules into two tiers: hard-fail errors (plain-text passwords, approved verbs, reserved parameters) and warnings that surface in the build log but do not fail the badge. `PSAvoidUsingWriteHost` is a warning only — all scripts in this repo are interactive admin tools that use `Write-Host` for color-coded output. Excludes the `archive/` folder.

**`Demo-Walkthrough.md`** (DEMO-ICAM-001)
Step-by-step live demonstration guide for portfolio reviews, hiring manager demos, and AO briefings. Covers seven steps: lock screen with no password option, card insertion and PIN prompt, Event 4768 Pre-Auth Type 16 in Event Viewer, session lock on card removal under two seconds, VPN connection via EAP-TLS without a password prompt, PKI health monitor green dashboard, and SCAP before/after compliance delta. Includes a hiring manager Q&A table and a NIST SP 800-53 controls-demonstrated table. Screenshot placeholder slots throughout for lab capture. Addresses NIST IA-2, IA-2(11), AC-11, AC-17, SC-8.

**`Lab-Kit/03-DomainController/New-YubiKeyToken.ps1`** (SCRIPT-ICAM-016)
YubiKey PIV provisioning script. Modes: Provision, Status, Reset, Verify. Generates a 24-byte random AES-256 management key (displayed once, never written to disk), enforces PIN/PUK complexity via `Test-TrivialPin`, generates keys in selected PIV slots (9a/9c/9d/9e) using ykman, submits a CSR to the Enterprise Issuing CA via `certreq.exe`, imports the returned certificate, and runs a post-issuance verification pass. Writes every ceremony step to a log file and Windows Event Log (EventID 7200, Source: YubiKeyProvisioning). All temporary CSR and certificate files are scrubbed after use. Addresses NIST AC-5, IA-2, IA-5.

#### Changed

**`README.md`**
Added CI status badges at the top of the file for the Secret Scan and PowerShell Lint GitHub Actions workflows.

**`Lab-Kit/01-HyperV-Host/New-LabVMs.ps1`**
Added drive auto-detection. When `-VMStoragePath` is left blank (new default), the script enumerates local fixed disks, calculates required space across all three VMs plus 15 GB overhead, scores each drive (prefers non-OS drives, prefers 2× headroom), displays a color-coded table (red = insufficient, yellow = OS drive, green = eligible), and prompts the operator to select a drive or enter a custom path.

**`Package-LabKit.ps1`**
Added a fourth packaging step that copies the `Live-Servers/` folder into the staging ZIP before it is written, so the self-contained USB kit includes the live server readiness and GPO compliance checkers alongside the lab scripts.

**`STATUS.md`**
Updated Phase 6 status to Automation Complete. Added SCRIPT-ICAM-016 (New-YubiKeyToken.ps1) entry. Added Live-Server Tooling and Lab Infrastructure sections.

**`ROADMAP.md`**
Corrected the Immediate Next Action path from the archived `Automation-Scripts` location to `Tools-Kit/Get-LabTools.ps1`. Added Step 0 (spin up Hyper-V VMs) and Step 7 (token enrollment including New-YubiKeyToken.ps1) to the lab execution sequence. Updated the YubiKey Phase 6 entry from pending to complete.

---

## [Phase 6 — Session 3] — 2026-05-22

### Lab Infrastructure & Live-Server Tooling

#### Added

**`Lab-Kit/01-HyperV-Host/New-LabVMs.ps1`**
Creates the three lab Hyper-V VMs: OfflineRootCA (Gen 2, 2 vCPU, 4 GB RAM, 80 GB VHDX), DC01 (Gen 2, 4 vCPU, 6 GB RAM, 100 GB VHDX), Workstation01 (Gen 2, 2 vCPU, 4 GB RAM, 80 GB VHDX). Attaches the Windows Server ISO, creates an internal virtual switch if none exists, and supports `-WhatIf`. Addresses NIST CM-6, CM-7.

**`Lab-Kit/01-HyperV-Host/Set-VMPostConfig.ps1`**
Post-OS configuration for each VM role after Windows Server installs. Sets static IP, enables WinRM, sets timezone, configures Windows Update, and applies role-specific configuration (DC, IssuingCA, OfflineRootCA, Workstation). Uses PowerShell Direct (`New-PSSession -VMName`) so no network is required.

**`Lab-Kit/01-HyperV-Host/Unattend-Server.xml`**
Unattended answer file for hands-free Windows Server installation on Generation 2 (UEFI/EFI) VMs. Configures locale, timezone, initial administrator password placeholder, and product key skip for evaluation media. Compatible with SCAP SCC scanning requirements.

**`Live-Servers/Test-ServerReadiness.ps1`**
Pre-deployment readiness checker for live (non-lab) servers. Accepts a `-Role` parameter (DC, IssuingCA, OfflineRootCA, Workstation) and runs role-appropriate checks before any provisioning script is executed. Reduces failed deployments from unmet prerequisites.

**`Live-Servers/Test-GPOCompliance.ps1`**
GPO existence, application, and registry settings validator. Confirms that the smart card enforcement GPO is linked and applied, and reads registry values for scforceoption, ScRemoveOption, and InactivityTimeoutSecs to verify the GPO took effect. Addresses NIST CM-6, IA-2(11).

**`Live-Servers/Install-Guide.md`**
Six-phase live server deployment walkthrough: infrastructure preparation, domain controller build, PKI two-tier setup, smart card enforcement GPO, workstation configuration, and validation. Written for deployment against real domain infrastructure rather than the lab.

**`Live-Servers/GPO-Check-Guide.md`**
How-to guide for running and interpreting Test-GPOCompliance.ps1. Covers expected output, common failure modes, and remediation steps for each registry check.

---

## [Phase 5 — Session 2] — 2026-05-21 to 2026-05-22

### RMF Authorize — ATO Package Templates & Advanced Automation Continued

#### Added

**`Architecture/RMF-Templates/SSP-Template.md`** (ARCH-ICAM-006)
System Security Plan template with system boundary narrative, environment description, interconnections table, full NIST SP 800-53 Rev. 5 control-by-control implementation statements for IA-2, IA-2(11), AC-5, AC-11, AC-17, SC-8, SC-17, CA-7, AU-2, and ATO decision block. Pre-populated with architecture-specific language throughout.

**`Architecture/RMF-Templates/POAM-Template.md`** (ARCH-ICAM-007)
Plan of Action and Milestones template with finding tracking table, risk acceptance register, deviation rationale column, and scheduled remediation dates. Structured to accept real data from Phase 4 SCAP SCC scans.

**`Architecture/RMF-Templates/SAR-Template.md`** (ARCH-ICAM-008)
Security Assessment Report template covering assessment scope and methodology, before and after compliance scores, CAT I/II/III finding counts, risk rating matrix, and assessor sign-off block.

**`Architecture/RMF-Templates/ATO-Letter-Template.md`** (ARCH-ICAM-009)
Authorizing Official memorandum template granting Authorization to Operate. Includes system name, authorization boundary, authorization date, expiration date, residual risk acceptance statement, and conditions of authorization.

**`Architecture/RMF-Templates/STIG-Deviation-Rationale.md`** (ARCH-ICAM-010)
Pre-populated STIG deviation rationale document with architecture-specific technical justifications for findings that require operational acceptance (e.g., CAPolicy.inf not present before CA role install during initial build).

**`Architecture/RMF-Templates/Annual-STIG-Rescan-SOP.md`** (ARCH-ICAM-011)
Standard Operating Procedure for annual STIG re-assessment and ATO renewal. Covers SCAP SCC scan execution, STIG Viewer checklist update, delta comparison against the prior year's SAR, POA&M update, and AO renewal submission sequence.

**`Architecture/RMF-Templates/CSET-Assessment-Guide.md`** (ARCH-ICAM-012)
CSET (Cyber Security Evaluation Tool) installation guide and question-set walkthrough. Covers CAC/PIV answer mapping for NIST 800-53, MD SB 871 compliance statement, and how to export the CSET results report for the ATO package.

**`Lab-Kit/03-DomainController/New-TokenEnrollment.ps1`** (SCRIPT-ICAM-011)
Two-phase token enrollment ceremony with enforced separation of duties. Phase 1 (Registration Authority): documents in-person photo-ID verification, records RA identity and verification timestamp, sets a signed authorization flag in Active Directory. Phase 2 (Card Issuer): reads the authorization flag, hard-blocks issuance if the same account attempted the RA phase, runs a pre-issuance checklist, and guides the technician through certificate enrollment and PIN setup. Every step is logged to file and Windows Application Event Log (EventID 4200). Addresses NIST AC-5, IA-2, IA-5.

**`Lab-Kit/03-DomainController/Monitor-PKIHealth.ps1`** (SCRIPT-ICAM-012)
PKI infrastructure health monitor for scheduled task execution. Downloads each CRL URL and parses the Next Update timestamp via certutil. Checks OCSP endpoint reachability, Issuing CA certificate expiry, VPN gateway certificate expiry, and enrolled user smart card certificate expiry against configurable day thresholds. Outputs a color-coded CRIT/WARN/OK dashboard to the console. Sends alert email if a threshold is crossed. Addresses NIST CA-7, SC-17.

**`Lab-Kit/03-DomainController/Set-AuditLogForwarding.ps1`** (SCRIPT-ICAM-013)
Audit policy and Windows Event Forwarding configurator. Collector mode configures the SIEM-side WEF subscription; Source mode applies audit policy on each monitored host via `auditpol`. Configures Advanced Audit Policy for all Kerberos, Logon, and Certification Services subcategories. WEF subscription pulls Event IDs 4624, 4625, 4768, 4769, 4776, 4886–4890, 4896, 4898 into the ForwardedEvents channel. Addresses NIST AU-2, AU-9, AU-12.

**`Lab-Kit/03-DomainController/New-CertificateTemplates.ps1`** (SCRIPT-ICAM-014)
AD CS certificate template builder using the PSPKI module. Creates two templates: a standard SmartCardLogon template (RSA 2048, auto-issue, Client Authentication + Smart Card Logon EKUs) and a privileged admin template (CA Manager approval required, restricted enrollment group). Includes a nine-step manual fallback guide printed to the console if PSPKI is unavailable. Publishes both templates to the CA. Addresses NIST SC-17, IA-5.

**`Lab-Kit/03-DomainController/Set-OCSPResponder.ps1`** (SCRIPT-ICAM-015)
Online Certificate Status Protocol (OCSP) setup script. Installs the Windows Online Responder role, requests an OCSP Response Signing certificate from the Issuing CA, and updates the CA's Authority Information Access (AIA) extension with the OCSP URL so all newly issued certificates carry the endpoint. Runs a live reachability test. Provides MMC walkthrough instructions for the revocation configuration step that cannot be fully automated. Addresses NIST SC-17, IA-5(2).

**`Portfolio/`** directory
Recruiter-facing deliverables: program showcase document, sanitized full blueprint, and sample manager brief.

---

## [Phase 3 — Session 1] — 2026-05-19 to 2026-05-21

### Compliance, Architecture Documents & Regulatory Alignment

#### Added

**`Architecture/PKI-Blueprint.md`** (ARCH-ICAM-001)
Two-tier PKI design document covering Offline Root CA (StandaloneRootCA, 4096-bit RSA, 10-year validity, air-gapped), Enterprise Issuing CA (EnterpriseSubordinateCA, 2048-bit RSA, 5-year validity, domain-joined), CRL/AIA publishing via HTTP (IIS), OCSP configuration, CAPolicy.inf contents, and key storage provider selection. Addresses NIST SC-17.

**`Architecture/STIG-Hardening-Guide.md`** (ARCH-ICAM-002)
SCAP SCC execution procedure covering tool installation, benchmark import, before-hardening scan, after-hardening scan, evidence staging with Stage-Reports.ps1, and STIG Viewer checklist completion for Windows Server 2022, AD DS, AD CS, and IIS. Addresses NIST CA-2, CA-7.

**`Architecture/NIST-CISA-Alignment.md`** (ARCH-ICAM-003)
Regulatory alignment document mapping the architecture to NIST SP 800-53 Rev. 5, NIST SP 800-63-3, FIPS 201-3, NIST SP 800-157, and CISA Cross-Sector Cybersecurity Performance Goals (CPG). Includes control-by-control implementation narrative and a mapping table.

**`Architecture/WatchGuard-IKEv2-VPN-Guide.md`** (ARCH-ICAM-004)
WatchGuard Firebox IKEv2 Mobile VPN configuration guide for EAP-TLS certificate authentication. Covers FIPS-compliant Phase 1 and Phase 2 crypto policies (AES-256-GCM, SHA-256, ECP384), CA trust anchor import, user group configuration, and client-side connection validation. Addresses NIST AC-17, SC-8.

**`Architecture/FedGov-Upgrade-Path.md`** (ARCH-ICAM-005)
Four-dimension federal upgrade path document covering the gap between the commercial baseline (CardLogix GIDS / HIRSCH uTrust tokens, software KSP, internal two-tier PKI, admin-desk enrollment) and full FISMA/FedRAMP compliance (GSA APL tokens, FIPS 140-3 Level 3 HSM, FBCA cross-certification, SP 800-157 derived credential kiosk enrollment).

**`Compliance-Reports/README.md`**
Staging area structure document with placeholder score fields for SCAP SCC before/after results, Nessus Essential finding counts, and STIG Viewer checklist status.

**`Tools-Kit/`** directory
- `Get-LabTools.ps1` — master downloader that orchestrates all three kit downloads in sequence
- `Download-FedCompliance-Kit.ps1` — DISA STIG Viewer, STIG content packs, SCAP 1.3 benchmarks, Microsoft Security Compliance Toolkit, Nessus Essentials, SysInternals, OpenSSL; generates TOOL-INDEX.md with RMF phase mapping
- `Download-OfflineCA-Kit.ps1` — SysInternals, OpenSSL, PSPKI for the air-gapped Root CA; generates CAPolicy.inf and CRL publication scripts; creates SHA-256 manifest for transfer verification
- `Download-IssuingCA-Kit.ps1` — AD CS Windows features, PSPKI, Initialize-IssuingCA.ps1 generation; optionally configures IIS for HTTP CRL/AIA publishing
- `START-HERE.md` — tool acquisition entry point and sequencing guide

---

## [Phase 2 — Session 1] — 2026-05-17 to 2026-05-19

### Core Automation Scripts

#### Added

**`Lab-Kit/03-DomainController/Build-CAC-Lab.ps1`**
Domain controller builder (Phase B). Installs the AD Domain Services role and promotes a clean Windows Server VM to a domain controller for a fresh `lab.local` forest with integrated DNS. Includes guardrails that refuse to run on an existing DC, supports `-WhatIf`, and writes a transcript log. Addresses NIST IA-2.

**`Lab-Kit/03-DomainController/Build-CA-GPO.ps1`**
Group Policy Object builder for smart card enforcement. Creates and links a GPO that sets `scforceoption = 1` (removes password logon option at the OS level), `ScRemoveOption = 1` (session lock on card removal), and `InactivityTimeoutSecs = 900`. Addresses NIST IA-2(11), AC-11.

**`Lab-Kit/04-Workstation/Enforce-SmartCard.ps1`**
Workstation-side smart card enforcement script. Applies the same registry values as the GPO for workstations that cannot receive Group Policy, enables the Smart Card service, and validates the configuration. Addresses NIST IA-2(11), AC-11.

**`Lab-Kit/04-Workstation/Deploy-VPNClient.ps1`**
IKEv2 VPN client profile deployment for Windows endpoints. Creates the connection, applies FIPS-compliant IPsec crypto (AES-256-GCM / SHA-256 / ECP384), builds the EAP-TLS XML to force smart card certificate authentication, and validates the configuration. Optionally runs a live connection test. Addresses NIST AC-17, SC-8.

**`Lab-Kit/05-Compliance/Stage-Reports.ps1`**
SCAP report harvester. Locates the most recent SCAP Compliance Checker output folder and copies the XCCDF XML and HTML reports into the `Before-MFA` or `After-MFA` staging directories.

---

## [Phase 1 — Session 1] — 2026-05-14 to 2026-05-17

### Foundation, Repository Structure & DevSecOps Controls

#### Added

**Repository initialized** with folder structure:
- `/Lab-Kit` — scripts organized by execution location (01-HyperV-Host through 05-Compliance)
- `/Tools-Kit` — tool acquisition scripts
- `/Architecture` — design and compliance documents
- `/Compliance-Reports` — SCAP SCC scan staging area (Before-MFA, After-MFA)
- `/Portfolio` — recruiter-facing deliverables
- `/Live-Servers` — live environment readiness and compliance tooling
- `/security` — repository security policy, contribution guide, incident response runbook

**`README.md`**
Full project overview covering architecture diagram, script inventory, NIST SP 800-53 control mapping, commercial vs. federal tier comparison, and repository security statement.

**`ROADMAP.md`**
Phase-by-phase build plan with RMF step alignment (Prepare → Categorize → Select → Implement → Assess → Authorize → Monitor), current phase tracker, and immediate next action.

**`STATUS.md`**
Living phase tracker with per-phase checklists and phase history table.

**`Scrub-Repo.ps1`**
Find-and-replace sanitizer. Reads a local-only `.scrub-patterns.local.json` (gitignored) and replaces real organizational identifiers with generic placeholders before any push. Run with `-WhatIf` to preview changes.

**`.scrub-patterns.example.json`**
Template patterns file showing the key/value format for the scrub map. The actual `.scrub-patterns.local.json` is gitignored and never committed.

**`Package-LabKit.ps1`**
Packages Lab-Kit, Tools-Kit, Live-Servers, and a docs snapshot into a self-contained ZIP for USB transfer to the Hyper-V host or air-gapped machines. Calculates a SHA-256 manifest for transfer integrity verification.

**`security/POLICY.md`**
Repository security policy covering what is never committed (private keys, active certificates, CA databases, real credentials, VM images) and the four-layer defense model (.gitignore, pre-commit hook, GitHub Actions secret scan, Scrub-Repo.ps1).

**`security/CONTRIBUTING.md`**
Secure contribution guide. Covers pre-commit hook installation, scrub-pattern setup, and the pre-push checklist.

**`security/INCIDENT_RESPONSE.md`**
Incident response runbook for accidental secret exposure in git history (BFG Repo-Cleaner procedure, GitHub support contact, credential rotation checklist).

**`security/scripts/pre-commit`**
Pre-commit hook that blocks private keys (PEM/PFX/P12), certificates, CA database files, VM image files (VHDX/VHD/OVA), and `.scrub-patterns.local.json` before they can be committed. Must be installed once per clone.

**`.github/workflows/secret-scan.yml`**
GitHub Actions workflow that re-runs the same checks as the pre-commit hook server-side on every push and pull request.

**`.gitignore`**
Excludes: private keys, certificates, CA databases, VM images, SCAP SCC binary installer, `.scrub-patterns.local.json`, `Conversation-Export-*.md`, IDE state folders (`.idea/`, `.vscode/`), PowerShell transcript logs.

**`Lab-Kit/START-HERE.md`**
Lab execution entry point. Documents the five-folder structure, pre-lab prerequisites, and the ordered sequence from VM creation through compliance scanning.

**`Lab-Kit/Reference/`**
Reference links back to canonical architecture documents in `/Architecture`, covering PKI blueprint, STIG hardening procedure, VPN guide, and federal upgrade path.

---

## Artifact ID Reference

| ID | File | Phase |
|---|---|---|
| ARCH-ICAM-001 | Architecture/PKI-Blueprint.md | 3 |
| ARCH-ICAM-002 | Architecture/STIG-Hardening-Guide.md | 3 |
| ARCH-ICAM-003 | Architecture/NIST-CISA-Alignment.md | 3 |
| ARCH-ICAM-004 | Architecture/WatchGuard-IKEv2-VPN-Guide.md | 3 |
| ARCH-ICAM-005 | Architecture/FedGov-Upgrade-Path.md | 3 |
| ARCH-ICAM-006 | Architecture/RMF-Templates/SSP-Template.md | 5 |
| ARCH-ICAM-007 | Architecture/RMF-Templates/POAM-Template.md | 5 |
| ARCH-ICAM-008 | Architecture/RMF-Templates/SAR-Template.md | 5 |
| ARCH-ICAM-009 | Architecture/RMF-Templates/ATO-Letter-Template.md | 5 |
| ARCH-ICAM-010 | Architecture/RMF-Templates/STIG-Deviation-Rationale.md | 5 |
| ARCH-ICAM-011 | Architecture/RMF-Templates/Annual-STIG-Rescan-SOP.md | 5 |
| ARCH-ICAM-012 | Architecture/RMF-Templates/CSET-Assessment-Guide.md | 5 |
| SCRIPT-ICAM-011 | Lab-Kit/03-DomainController/New-TokenEnrollment.ps1 | 6 |
| SCRIPT-ICAM-012 | Lab-Kit/03-DomainController/Monitor-PKIHealth.ps1 | 6 |
| SCRIPT-ICAM-013 | Lab-Kit/03-DomainController/Set-AuditLogForwarding.ps1 | 6 |
| SCRIPT-ICAM-014 | Lab-Kit/03-DomainController/New-CertificateTemplates.ps1 | 6 |
| SCRIPT-ICAM-015 | Lab-Kit/03-DomainController/Set-OCSPResponder.ps1 | 6 |
| SCRIPT-ICAM-016 | Lab-Kit/03-DomainController/New-YubiKeyToken.ps1 | 6 |
| DEMO-ICAM-001 | Demo-Walkthrough.md | 6 |

---

*See `STATUS.md` for current phase progress. See `ROADMAP.md` for what comes next.*
