📖 Runbook: Executing Automated STIG Hardening & Compliance Audits

Document ID: ARCH-ICAM-002
Author: Glenn Byron
Framework: DISA RMF | NIST SP 800-53 CA-2, CA-7 | DISA STIG

This runbook covers the end-to-end process for running DISA STIG compliance scans against lab VMs using free, publicly available DoD tools — before and after applying the hardening scripts. The goal is a documented before/after evidence trail for the RMF Assess phase.

> **v1.4 milestone (2026-06-30):** the manual SCAP scan workflow below produces the
> baseline evidence. The automated remediation pipeline that drives scores up is
> in [`Lab-Kit/08-Ansible-STIG/`](../Lab-Kit/08-Ansible-STIG/) — the
> ansible-lockdown Windows-2022-STIG role driven from a WSL2 control node on
> the Hyper-V host. Applied to LAB-DC01 in three severity-tagged phases
> (CAT I → II → III) with snapshot + `win_ping` verification between each.
> Result: **44.95% baseline → 86.7% post-remediation.** Scan archives at
> [`Compliance-Reports/After-Ansible/`](../Compliance-Reports/After-Ansible/).
> See `Lab-Kit/08-Ansible-STIG/GUIDE.md` for the step-by-step runbook and
> `Lab-Kit/08-Ansible-STIG/CHANGELOG.md` for the four Server-2025 + ansible-core
> 2.21 compatibility patches that were required.
________________________________________
🛰️ Step 1: Procurement of Authoritative DoD Tools
Always pull STIG benchmarks and scanning tools directly from DISA. This keeps the files authoritative and ensures the chain of custody is clean.
1.1 Download the SCAP Compliance Checker (SCC)
1.	Navigate to the official DoD Cyber Exchange STIG Tools Portal.
2.	Scroll to the SCAP Compliance Checker (SCC) distribution section.
3.	Download the installer for your host machine (e.g., SCC_Windows_X64.zip or the matching Linux .rpm).
1.2 Download the Matching Security Benchmarks
1.	From the same portal, download the automated SCAP Content library that matches your target virtual machine operating system (e.g., Windows Server SCAP Content or Red Hat Enterprise Linux SCAP Content).
2.	Save these archives to an isolated configuration directory on your staging workstation.
________________________________________
⚙️ Step 2: Installation and Staging
2.1 Installing the Scanning Engine (Windows Example)
1.	Extract the downloaded SCC_Windows_X64.zip archive into a local temporary folder.
2.	Right-click SCC_Installer.exe and select Run as Administrator (elevated tokens are required to query local security structures).
3.	Complete the installation wizard using the default system target path (C:\Program Files\SCAP Compliance Checker\).
2.2 Importing Security Baselines
1.	Launch the SCAP Compliance Checker application.
2.	Select Options from the top menu bar -> click Import SCAP Content.
3.	Point the application to the unzipped SCAP benchmark content folder you downloaded in Step 1.2. The tool will parse and register the official .XCCDF rules engine.
________________________________________
⚡ Step 3: Executing the Audit Cycle
[Select Target System] ➔ [Load SCAP Content Profile] ➔ [Click: Start Scan]
3.1 Capturing the "Before-MFA" Baseline
1.	Under the Local Scanning panel, select your target operating system profile.
2.	Uncheck any extraneous benchmarks to keep the audit footprint clean and focused on your specific system.
3.	Click the prominent Start Scan button.
4.	The scanner will run local script checks, read registry branches, evaluate user access lists, and determine system vulnerabilities.
3.2 Executing Remediation
1.	Run your automated hardening code blocks (.\Build-CAC-Lab.ps1 and .\Enforce-SmartCard.ps1).
2.	Force a full system state refresh by restarting the target virtual machine.
3.3 Capturing the "After-MFA" High-Compliance State
1.	Re-open the SCAP Compliance Checker.
2.	Click Start Scan once more to evaluate the active, hardened state of the operating system.
________________________________________
💾 Step 4: Exporting and Saving Report Data
Once a scanning cycle completes, the engine generates individual output folders. Follow these steps to parse and format them for your GitHub repository:
4.1 Exporting the Metrics
1.	Within SCC, navigate to the Session Results tab -> choose View Reports.
2.	Select Export Results from the sub-menu.
3.	Export the file in two distinct formats:
o	HTML Report: Provides an easily readable web layout mapping every Pass / Fail rule, complete with fix statements.
o	XCCDF Results XML: A machine-readable data package required to build digital compliance pipelines or feed into the official DISA STIG Viewer application.

________________________________________
💾 Step 5: Structuring the Data for the Repository
Organize the exported SCAP reports into the repository's Compliance-Reports tracking directories so a reviewer can see the before/after improvement at a glance. Use the automated staging utility (Stage-Reports.ps1) in the repository root, which copies the most recent SCC run into the correct tier folder:

```powershell
# Preview what would be staged (no files changed)
.\Stage-Reports.ps1 -WhatIf

# Stage the baseline (pre-hardening) scan
.\Stage-Reports.ps1            # choose option 1 when prompted

# After remediation + rescan, stage the hardened scan
.\Stage-Reports.ps1            # choose option 2 when prompted
```

Target structure:

```text
Compliance-Reports/
├── README.md                  <-- Scoring summary table (Step 6.4)
├── Before-MFA/
│   ├── Baseline-Report.html        <-- SCAP STIG report (pre-hardening)
│   └── Baseline-Vulnerability.pdf  <-- ACAS / Nessus baseline (Step 6)
└── After-MFA/
    ├── Hardened-Report.html        <-- SCAP STIG report (post-hardening)
    └── Hardened-Vulnerability.pdf  <-- ACAS / Nessus hardened (Step 6)
```

________________________________________
🔍 Step 6: Enterprise Vulnerability Scanning & ACAS Integration
SCAP scans evaluate system *configuration* (STIG compliance). A vulnerability scanner is a different lens: it looks for active unpatched software, missing security updates, and exposed cryptographic protocols. DoD Risk Management Framework (RMF) guidelines require both. ACAS (Assured Compliance Assessment Solution, built on Tenable Nessus) is the tool DoD auditors use for the vulnerability half.

```text
[Target Staging VM] -> [SCAP Scan (STIGs)] -> [ACAS Scan (Vulnerabilities)] -> [Remediate]
```

### 6.1 Configuring the ACAS / Nessus Scanner Environment
1.	Ensure the scanner has a clear network route to the isolated target VM inside the private lab virtual switch.
2.	On the scanner dashboard, configure a new Advanced Network Scan against the target VM's IP address.
3.	Under Credentials, provide administrative access (Windows Domain Admin, or Linux root via SSH key).
	o	Compliance note: scans MUST be authenticated. Unauthenticated scans only see perimeter ports and miss deep OS-level findings.

### 6.2 Executing the Scanning Cycle
1.	Initial baseline scan (before hardening): run an initial scan to discover open vulnerabilities — old patch states, weak ciphers, outdated third-party software.
2.	Post-hardening scan (after hardening): after deploying the lab build scripts, the smart-card GPOs, and the MFA configuration, restart the target VM and run a second scan to verify remediation.

### 6.3 Saving and Structuring Vulnerability Data
Export the ACAS findings in two formats and place them alongside the SCAP data using Stage-Reports.ps1:
*	Executive PDF Summary: readable Critical / High / Medium / Low breakdown.
*	Raw .nessus XML Data Package: the authoritative file with every finding, patch link, and remediation vector.

### 6.4 Repository Summary Dashboard
Update Compliance-Reports/README.md with the before/after scoring so a reviewer sees the improvement immediately. Example layout (replace with your real lab numbers):

| Audit Stage | SCAP STIG Score | ACAS Critical / High | Target Security Tier |
| :--- | :--- | :--- | :--- |
| Initial Baseline (Before MFA) | _replace with your score_ | _replace with your count_ | Vulnerable Topology |
| Hardened Infrastructure (After MFA) | _replace with your score_ | _replace with your count_ | Audit-Ready Baseline |

________________________________________
🚀 Complete Workflow Summary
The full local workflow, end to end:
1.	Scan 1 (clean VM): run the initial SCC baseline scan.
2.	Stage 1: run .\Stage-Reports.ps1 and choose option 1 to lock it into the Before-MFA path.
3.	Remediate: run the lab build scripts and the GPO scripts, then restart the VM.
4.	Scan 2 (secured VM): run the post-hardening verification scan.
5.	Stage 2: run .\Stage-Reports.ps1 and choose option 2 to lock it into the After-MFA path.
6.	Push: stage, commit, and push (after running Scrub-Repo.ps1 -WhatIf to confirm no real identifiers leak).

________________________________________
This runbook documents free, publicly available DoD and federal tools (DISA SCAP Compliance Checker, DISA STIG Viewer, CISA CSET, ACAS/Nessus) used in an isolated lab. It contains no organizational data. Part of the optional Federal Compliance / Testing track; see Architecture/Federal-Compliance-Upgrade.md for the broader upgrade path.

