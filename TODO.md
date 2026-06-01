# CAC Program — Outstanding Tasks

**Author:** Glenn Byron
**Last Updated:** May 29, 2026

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

## DevSecOps — Pipeline and IaC

### CI/CD Security Pipeline (GitHub Actions)
- ✅ Secret & sensitive file scan — blocks private keys and cert files
- ✅ PowerShell lint (PSScriptAnalyzer) — enforces approved verbs, no plaintext passwords
- ✅ CodeQL SAST — static analysis on Python code, weekly scheduled scan
- ✅ Trivy container scan — CVE scanning on Docker images, daily scheduled scan
- ✅ Dependency review — blocks PRs with HIGH/CRITICAL CVEs in new dependencies
- ⬜ Add SBOM generation (Syft or `trivy sbom`) on container build — EO 14028 compliance
- ⬜ Add Gitleaks workflow for deeper secret detection beyond the current scan

### Container
- ✅ `docker/scap-summary/` — containerized SCAP XCCDF parser, multi-stage Dockerfile, non-root
- ⬜ Push image to GitHub Container Registry (ghcr.io) on merge to main
- ⬜ Add Docker content trust / image signing (cosign) — supply chain integrity

### Infrastructure as Code (Ansible)
- ✅ `Lab-Kit/Ansible/windows-stig-hardening.yml` — automates 8 STIG sections on Windows Server
- ⬜ Add Ansible playbook for AD health check (stale accounts, privileged group audit)
- ⬜ Add Ansible playbook for certificate expiry reporting
- ⬜ Run hardening playbook against physical lab machines once they're set up

### Next Learning Targets
- ⬜ AZ-500 (Azure Security Engineer) — builds on AZ-900, high DoD value
- ⬜ Certified DevSecOps Professional (CDP) from Practical DevSecOps
- ⬜ WGU MSSWEDOE — enroll after starting new job, use tuition assistance

---

## Physical Lab Setup (Dell Hardware Path)

- ⬜ Pull service tags and verify Server 2022 support for each machine at dell.com/support
- ⬜ Update iDRAC firmware on all PowerEdge servers (via Lifecycle Controller or manual upload)
- ⬜ Set static IPs and change default passwords on all iDRAC interfaces
- ⬜ Configure VLAN segmentation on managed switch (VLAN 10 Lab-LAN, VLAN 1 Management)
- ⬜ Install Server 2022 on DC01 via iDRAC virtual media or USB
- ⬜ Install Server 2022 on MEMBER01
- ⬜ Install Dell OpenManage Server Administrator on each PowerEdge
- ⬜ Verify TPM 2.0 enabled on all machines (BIOS → Security → TPM)
- ⬜ Apply iDRAC 9 STIG items (default password, TLS 1.2+, session timeout, audit logging)
- ⬜ Proceed from `Lab-Kit/02-OfflineRootCA/` — scripts are hardware-agnostic from this point

Full setup guide: `Lab-Kit/Physical-Lab-Setup.md`

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

## Phase 8 — Zero Trust Extension (After Phase 4)

Design complete. Scripts are the next build phase. Full design in `Lab-Kit/Phase-8-Zero-Trust-Extension.md`.

### 8.1 — Authorization & Least Privilege
- ⬜ `Set-TieredAdminModel.ps1` — AD admin tiering (Tier 0/1/2), OUs, groups, deny-logon rules
- ⬜ `Set-LeastPrivilegeGPO.ps1` — User Rights Assignment hardening, strip broad local-admin
- ⬜ `New-RBACModel.ps1` — role groups, role → resource mapping, AD delegation
- ⬜ `Set-AuthenticationPolicySilo.ps1` — Kerberos Authentication Policy Silos
- ⬜ `Deploy-ResourceGateway.ps1` — reverse proxy / app gateway as working PEP demo

### 8.2 — Device Trust
- ⬜ `New-DeviceCertTemplate.ps1` — machine-authentication cert template from Issuing CA
- ⬜ `Enroll-DeviceCertificates.ps1` — device cert autoenrollment
- ⬜ `Set-DeviceComplianceCheck.ps1` — pre-access posture gate (AV, patch, BitLocker)
- ⬜ `Update-VPN-DeviceAuth.ps1` — require both user and machine certs on VPN

### 8.3 — Continuous & Conditional Access
- ⬜ `Set-KerberosTicketLifetime.ps1` — shorten TGT/TGS lifetimes via Authentication Policies
- ⬜ `Deploy-ConditionalAccess.ps1` — PIV federation into Entra ID / AD FS with conditional access
- ⬜ `New-RiskPolicy.ps1` — step-up and deny conditions, Continuous Access Evaluation

### 8.4 — Workload / Non-Person Identity *(optional)*
- ⬜ `New-WorkloadCertTemplate.ps1` — short-lived service/machine identity cert template
- ⬜ `Set-ServiceAccountHardening.ps1` — convert to gMSA, remove stored secrets
- ⬜ `Enable-mTLS.ps1` — mutual TLS between two lab services

### 8.5 — Network Segmentation & Per-App Access
- ⬜ `Set-Microsegmentation.ps1` — default-deny east-west between lab VMs
- ⬜ `Convert-VPNToPerApp.ps1` — per-resource VPN access (ZTNA-style)

### 8.6 — Visibility, Analytics → Decisioning
- ⬜ `Deploy-SIEM.ps1` — forward WEF stream into Sentinel or Elastic
- ⬜ `New-DetectionRules.ps1` — anomalous auth, lateral movement, policy violation detections
- ⬜ `Connect-Analytics-To-Policy.ps1` — risk signal feeds back into conditional access

### 8.7 — Validation & Evidence
- ⬜ `Invoke-ZeroTrustValidation.ps1` — extend 7-layer validator with ZT checks
- ⬜ Extend `Stage-Reports.ps1` with Before-ZT / After-ZT delta
- ⬜ Update SSP control mapping with Phase 8 control families
- ⬜ Add `Demo-Walkthrough-ZT.md`

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
| Phase 8 — Zero Trust Extension | ⬜ Design complete / scripts pending |

---

*Full execution sequence: `Lab-Kit/START-HERE.md` → `Lab-Kit/LAB-DAY-CHECKLIST.md`*
*RMF template population: `Architecture/RMF-Templates/`*
*Demo guide: `Demo-Walkthrough.md`*
