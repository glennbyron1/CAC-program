# Changelog — CAC/PIV ICAM Portfolio

**Author:** Glenn Byron
**Project:** Enterprise ICAM: CAC-Style Identity & Access Deployment Blueprint
**Format:** Chronological by build session, organized by program phase.

This log covers every artifact produced across the life of the project — scripts, architecture documents, compliance templates, lab infrastructure, and DevSecOps controls. Entries show what was built, the NIST control addressed, and the document ID assigned at the time.

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
