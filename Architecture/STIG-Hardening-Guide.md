📖 Runbook: Executing Automated STIG Hardening & Compliance Audits
This document defines the standard operating procedure (SOP) for downloading, installing, executing, and archiving compliance evaluations across enterprise virtual machine baselines utilizing official Department of Defense (DoD) utilities.
________________________________________
🛰️ Step 1: Procurement of Authoritative DoD Tools
Federal compliance guidelines require obtaining security benchmarks directly from the Defense Information Systems Agency (DISA) repository to ensure file integrity and supply chain validity.
1.1 Download the SCAP Compliance Checker (SCC)
1.	Navigate to the official DoD Cyber Exchange STIG Tools Portal.
2.	Scroll to the SCAP Compliance Checker (SCC) distribution section.
3.	Download the appropriate architect file for your host machine (e.g., SCC_Windows_X64.zip or the matching Linux .rpm package).
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

