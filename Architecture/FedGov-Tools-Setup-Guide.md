# Federal Government Compliance Tools — Setup & Usage Guide

Document ID: ARCH-ICAM-004
Author: Glenn Byron
Framework: DISA RMF | NIST SP 800-53 CA-2, CA-7 | CISA CPG 5.A | MD SB 871 §9-2705(b)(3)

> **Run Order:** Use `Download-FedCompliance-Kit.ps1` to stage all tools before
> following this guide. Scanning procedures map directly to the before/after
> compliance workflow in `STIG-Hardening-Guide.md`.

---

## Tool Overview

| Tool | Source | Auth | Role in RMF |
|------|--------|------|-------------|
| SCAP Compliance Checker (SCC) | DISA cyber.mil | CAC (or public try) | STIG automated scan — Assess phase |
| DISA STIG Viewer 3.3 | DISA public.cyber.mil | None | STIG checklist review — Select phase |
| DISA STIG Content | DISA public.cyber.mil | None | XCCDF rules imported into SCC and STIG Viewer |
| Microsoft Security Compliance Toolkit | Microsoft Download | None | STIG-aligned GPO baseline deployment — Implement phase |
| Microsoft Policy Analyzer | Microsoft Download | None | Compare current GPO settings against SCT baseline |
| Nessus Essentials | Tenable.com | Free registration | Vulnerability scan (ACAS equivalent) — Assess phase |
| CISA CSET | GitHub (cisagov) | None | OT/ICS/IT cybersecurity self-assessment |
| SysInternals sigcheck | Microsoft | None | Certificate chain and binary integrity verification |
| OpenSSL | slproweb.com | None | Manual CRL and certificate chain inspection |

---

## 1. SCAP Compliance Checker (SCC) — STIG Automated Scanning

The SCAP Compliance Checker is the primary DoD tool for automated STIG compliance
auditing. It ingests DISA SCAP 1.3 benchmark content and produces machine-readable
XCCDF results and human-readable HTML reports.

### 1.1 Installation

1. Locate the SCC installer in `00-SCAP-SCC\SCC-Windows-Bundle.zip`
   - If not downloaded (CAC-gated): go to https://public.cyber.mil/stigs/scap/
   - Try the direct link first — SCC is sometimes available without CAC login
2. Extract the zip to a local temp folder
3. Right-click `SCC_Installer.exe` → **Run as Administrator**
4. Complete the installation wizard — accept the default install path:
   `C:\Program Files\SCAP Compliance Checker\`
5. Launch the SCAP Compliance Checker from the Start menu

### 1.2 Importing SCAP Content (Benchmark Files)

1. Open SCAP Compliance Checker
2. Select **Options** → **Import SCAP Content**
3. Navigate to `03-SCAP-Content\Windows-Server-2022\` and select the extracted
   SCAP 1.3 benchmark `.zip` file
4. Repeat for each OS you will scan (Server 2019, Windows 11, etc.)
5. The XCCDF rules engine will parse and register all benchmarks
6. Verify content appears in the **SCAP Content** panel on the left

### 1.3 Executing the "Before-MFA" Baseline Scan

Run this scan on the **clean, unmodified** lab VM before any hardening:

1. In the **Local Scanning** panel, select your target OS benchmark
   (e.g., `Microsoft Windows Server 2022 STIG`)
2. Uncheck any extraneous benchmarks — keep the scan focused on your OS
3. Click **Start Scan**
4. The scanner queries registry keys, local policy, user rights assignments,
   service configurations, and audit policy settings
5. Wait for scan completion (typically 5–20 minutes)
6. Note the **Score (%)** in the Session Results tab

### 1.4 Exporting Reports

1. Navigate to **Session Results** → **View Reports**
2. Select **Export Results**
3. Export in **two formats**:
   - **HTML Report** — human-readable Pass/Fail with fix statements for each rule
   - **XCCDF Results XML** — machine-readable; required for STIG Viewer and DISA pipelines
4. Stage these files using `Stage-Reports.ps1`:

```powershell
# Preview what would be staged
.\Stage-Reports.ps1 -WhatIf

# Stage the pre-hardening baseline
.\Stage-Reports.ps1    # Select option 1 (Before-MFA)
```

### 1.5 Executing the "After-MFA" Post-Hardening Scan

After running hardening scripts and applying smart card GPOs:

1. Restart the target VM to apply all policy changes
2. Re-open SCAP Compliance Checker
3. Select the same benchmark used in step 1.3
4. Click **Start Scan**
5. Export results and stage using `.\Stage-Reports.ps1` → option 2 (After-MFA)
6. Update `Compliance-Reports\README.md` with your before/after scores

---

## 2. DISA STIG Viewer — Checklist Review and Manual Findings

STIG Viewer is a graphical tool for reviewing individual STIG rules, recording
manual check results, and producing a completed checklist (CKL file) for
authorization packages.

### 2.1 Installation

1. Extract `01-STIG-Viewer\STIGViewer-3-3.zip`
2. Option A (installer): run `STIGViewer-3-3_Installer.exe`
3. Option B (portable jar): `java -jar STIGViewer-3-3.jar` (requires Java 11+)
4. First launch: accept the EULA

### 2.2 Loading STIG Content

1. Open STIG Viewer
2. **File** → **Import STIG** → navigate to `02-STIG-Content\Windows-Server-2022\`
3. Select the XCCDF XML file (e.g., `U_MS_Windows_Server_2022_V2R2_Manual-xccdf.xml`)
4. The STIG loads in the left panel with all CAT I, II, III findings listed

### 2.3 Reviewing Findings

Each STIG rule has a **Check** statement (what to look for) and a **Fix** statement
(remediation command). Work through each finding:

- **Open (CAT I)** — Critical: must remediate before authorization
- **Open (CAT II)** — High: remediate for audit-ready baseline
- **Open (CAT III)** — Medium: remediate where feasible
- **Not a Finding** — mark after verifying the control is satisfied
- **Not Applicable** — mark if the rule does not apply to this system role

### 2.4 Importing SCAP Results into STIG Viewer

To merge automated SCC results with manual review:

1. In STIG Viewer: **File** → **Import XCCDF Results**
2. Navigate to the XCCDF XML exported from SCC in Section 1.4
3. SCC-evaluated rules automatically populate with Pass/Fail status
4. Manually review remaining rules that SCC could not evaluate automatically

### 2.5 Exporting the Completed Checklist (CKL)

**File** → **Save Checklist** → save as `.ckl` file. The CKL is the standard
deliverable for DISA authorization packages and Security Assessment Reports.

---

## 3. Microsoft Security Compliance Toolkit (SCT) & Policy Analyzer

The Microsoft SCT provides pre-built Group Policy baselines aligned to DISA STIG
requirements for Windows endpoints. Policy Analyzer compares the baseline against
current GPO settings to identify gaps.

### 3.1 Extracting the Toolkit

```powershell
# Extract to a permanent location
Expand-Archive -Path "04-MS-Security-Compliance-Toolkit\MS-SecurityBaseline-WinServer2022.zip" `
               -DestinationPath "C:\SCT\WinServer2022" -Force

Expand-Archive -Path "04-MS-Security-Compliance-Toolkit\PolicyAnalyzer.zip" `
               -DestinationPath "C:\SCT\PolicyAnalyzer" -Force
```

### 3.2 Importing Baselines into Policy Analyzer

1. Launch `C:\SCT\PolicyAnalyzer\PolicyAnalyzer.exe`
2. **File** → **Import** → navigate to `C:\SCT\WinServer2022\`
3. Select the `.PolicyRules` file (e.g., `MSFT-Win2022-MS-Member-Server.PolicyRules`)
4. The baseline loads in the left panel
5. **View** → **Compare to local GP** — shows delta between baseline and current settings

### 3.3 Deploying SCT Baselines via LGPO.exe

The SCT includes `LGPO.exe` for local policy import (useful in lab environments
without a domain):

```powershell
# Import the Server 2022 member server baseline
C:\SCT\WinServer2022\Scripts\Baseline-LocalInstall.ps1 -Win2022MemberServer
```

For domain environments, import the included GPO backups via Group Policy
Management Console:

1. Open **Group Policy Management** (`gpmc.msc`)
2. Right-click your target OU → **Import Settings**
3. Navigate to `C:\SCT\WinServer2022\GPOs\`
4. Import the appropriate baseline GPO

---

## 4. Nessus Essentials — Authenticated Vulnerability Scanning

Nessus Essentials is the free tier of Tenable Nessus, which is the same engine
used by DoD ACAS (Assured Compliance Assessment Solution). It supports up to 16
IP addresses with full authenticated scanning capability.

### 4.1 Installation and Activation

1. Run `05-Nessus-Essentials\Nessus-*.msi` as Administrator
2. The Nessus service starts automatically after install
3. Open browser: `https://localhost:8834`
4. Product selection screen → select **Nessus Essentials**
5. If you have an activation code: enter it and skip to step 7
6. If not: **Get an activation code** → register at tenable.com (free, email required)
7. Create an admin username and password
8. **Plugin Update**: Nessus downloads and compiles ~90,000 plugins (~15-20 minutes)

### 4.2 Configuring a Credentialed Scan

Unauthenticated scans miss deep OS-level findings. DoD RMF requires credentialed scans.

1. Nessus dashboard → **New Scan** → **Advanced Network Scan**
2. **Settings** tab:
   - Name: `CAC-Lab Credentialed Baseline`
   - Targets: IP address of your lab CA/domain server
3. **Credentials** tab → **+** → **Windows**:
   - Authentication method: **Password**
   - Username: `lab\Administrator` (or your domain admin UPN)
   - Password: `<admin password>`
   - Domain: `lab.local`
4. **Plugins** tab: verify the following plugin families are enabled:
   - Windows, Windows: Microsoft Bulletins, Misc., Settings
5. **Save** → **Launch**

### 4.3 Reviewing Scan Results

After scan completion (~10–30 minutes depending on target):

- **Critical / High** findings → must remediate before After-MFA scan
- Key finding categories for a CA server:
  - Missing Windows patches
  - Weak cipher suites on RDP / IIS
  - SMB signing not enforced
  - Null session enumeration
  - SSL/TLS certificate issues on the HTTP CRL endpoint

### 4.4 Exporting for the Repository

```
Scan name → Report tab → Export → PDF (Executive Summary)
```

Save files to:
- `Compliance-Reports\Before-MFA\Baseline-Vulnerability.pdf` — pre-hardening
- `Compliance-Reports\After-MFA\Hardened-Vulnerability.pdf` — post-hardening

Update the scoring table in `Compliance-Reports\README.md`.

---

## 5. CISA Cybersecurity Evaluation Tool (CSET)

CSET is a CISA-developed self-assessment tool that walks administrators through
structured cybersecurity assessments mapped to NIST, NERC CIP, and other
frameworks. It is specifically relevant for organizations subject to Maryland
Senate Bill 871 (water/wastewater cybersecurity) as it covers OT/ICS environments.

### 5.1 Installation

1. Run `08-CISA-CSET\CSET_Installer.exe` as Administrator
2. Follow the installation wizard (default path: `C:\Program Files\CSET\`)
3. Launch CSET from the Start menu or desktop shortcut
4. On first launch, create a local assessment account

### 5.2 Creating an Assessment

1. **New Assessment** → enter system name and description
2. **Framework Selection** → select applicable frameworks:
   - **NIST CSF 2.0** — for general enterprise alignment
   - **CISA CPG** — for Cross-Sector Cybersecurity Performance Goals
   - **NIST SP 800-82** — for OT/ICS systems (relevant under MD SB 871)
3. Work through the questionnaire — each question maps to specific controls
4. CSET scores each domain and provides a maturity level

### 5.3 Generating Assessment Reports

**Reports** → **Generate Report** → export PDF assessment summary. CSET reports
document current maturity level and recommended improvements for each framework.

These reports support the MD SB 871 §9-2705(b)(3) requirement for annual
third-party assessment of IT/OT systems.

---

## 6. SysInternals sigcheck — Certificate Chain Verification

sigcheck verifies that binaries are signed and reports the full certificate chain.
Use it to confirm smart card certificates chain correctly to the Root CA.

### 6.1 Basic Usage

```powershell
# Extract SysInternals
Expand-Archive -Path "06-SysInternals\SysinternalsSuite.zip" `
               -DestinationPath "C:\Sysinternals" -Force

# Verify a certificate in the local machine store
C:\Sysinternals\sigcheck64.exe -v -a "C:\Path\To\SignedBinary.exe"

# Display all certificates in local machine My store
certutil -store My

# Verify the CRL is reachable and valid
certutil -verify -urlfetch "C:\Windows\System32\CertSrv\CertEnroll\IssuingCA.crl"
```

### 6.2 Run the Bundled Verification Script

```powershell
# Verify all smart card logon certificates in local machine store
.\06-SysInternals\Verify-CertificateChain.ps1
```

---

## 7. OpenSSL — Manual CRL and Certificate Inspection

OpenSSL allows manual inspection of CRL files, certificate chains, and OCSP
responses without relying on Windows tooling.

### 7.1 Installation

1. Run `07-OpenSSL\Win64OpenSSL_Light.exe` as Administrator
2. Add to PATH: `C:\Program Files\OpenSSL-Win64\bin\`

### 7.2 Common Commands for PKI Verification

```powershell
# Inspect a CRL file
openssl crl -inform DER -in IssuingCA.crl -text -noout

# Verify a certificate against the CA chain
openssl verify -CAfile RootCA.crt -untrusted IssuingCA.crt UserCert.crt

# Inspect a certificate
openssl x509 -in UserCert.crt -text -noout

# Test HTTP CRL endpoint reachability
# Download CRL via curl (included in Windows 10+)
curl -o IssuingCA.crl http://crl.agency.gov/crl/IssuingCA.crl
openssl crl -inform DER -in IssuingCA.crl -text -noout | Select-String "Next Update"

# Test OCSP response
openssl ocsp -issuer IssuingCA.crt -cert UserCert.crt `
             -url http://ocsp.agency.gov/ -resp_text
```

---

## 8. Complete Workflow — Before/After Compliance Audit

End-to-end procedure tying all tools together:

```text
[Clean VM]
    │
    ├─► Nessus Essentials scan (credentialed) → Baseline-Vulnerability.pdf
    │
    ├─► SCAP SCC scan (XCCDF benchmark) → Baseline-Report.html + XCCDF XML
    │
    ├─► Stage-Reports.ps1 (option 1 — Before-MFA) → Compliance-Reports\Before-MFA\
    │
    ├─► CSET assessment → document initial maturity level
    │
    ↓
[Run Build-CAC-Lab.ps1, Build-CA-GPO.ps1, apply smart card GPOs]
    │
    ├─► Restart VM
    │
    ├─► Nessus Essentials scan (credentialed) → Hardened-Vulnerability.pdf
    │
    ├─► SCAP SCC scan → Hardened-Report.html + XCCDF XML
    │
    ├─► Stage-Reports.ps1 (option 2 — After-MFA) → Compliance-Reports\After-MFA\
    │
    ├─► STIG Viewer → import XCCDF XML → record remaining manual findings
    │
    ├─► Policy Analyzer → verify SCT baseline delta closed
    │
    └─► Update Compliance-Reports\README.md scoring table
```

---

## 9. MD SB 871 §9-2705(b)(3) — Annual Assessment Reference

Maryland Senate Bill 871 requires an **annual third-party assessment of IT/OT devices**.
The tools in this guide support that requirement:

| Tool | Assessment Scope | SB 871 Relevance |
|------|-----------------|-----------------|
| SCAP SCC | IT system STIG compliance | Annual configuration audit |
| Nessus Essentials | Vulnerability posture | Annual vulnerability assessment |
| CISA CSET | OT/ICS maturity (PACS, SCADA) | OT device assessment per §9-2701(E)(2) |
| STIG Viewer | Manual control verification | Documents evidence for assessors |
| Policy Analyzer | GPO baseline compliance | Policy drift detection |

Maintain all exported reports for a minimum of **three years** per
Regulatory-Alignment.md Section 4.5 (post-incident record retention).

---

*This guide is maintained as part of the CAC/PIV Program compliance track.
For PKI architecture, see `Architecture/Blueprint.md`. For SCAP scan
staging automation, see `Stage-Reports.ps1`. For regulatory mapping,
see `Architecture/Regulatory-Alignment.md`.*
