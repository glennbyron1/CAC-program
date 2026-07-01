# CAC/PIV Lab — RMF, STIG, and Vulnerability Scanning Learning Guide

**Author:** Glenn Byron
**Lab Completed:** 2026-05-27
**Purpose:** Everything learned building and running a full CAC/PIV ICAM lab —
concepts, tools, gotchas, and real-world application.

---

## Table of Contents

1. [What This Lab Is and Why It Matters](#1-what-this-lab-is-and-why-it-matters)
2. [The RMF Framework — What It Is and How This Lab Implements It](#2-the-rmf-framework)
3. [PKI — How Certificate-Based Authentication Works](#3-pki-how-certificate-based-authentication-works)
4. [Smart Card / CAC / PIV — The Full Chain](#4-smart-card--cac--piv---the-full-chain)
5. [Active Directory and GPO Enforcement](#5-active-directory-and-gpo-enforcement)
6. [STIG Compliance — What It Means and How to Measure It](#6-stig-compliance)
7. [SCAP and SCC — The Scanning Tools](#7-scap-and-scc---the-scanning-tools)
8. [Vulnerability Scanning vs. Compliance Scanning](#8-vulnerability-scanning-vs-compliance-scanning)
9. [Before/After MFA Scan Methodology](#9-beforeafter-mfa-scan-methodology)
10. [Key Bugs Found and Lessons Learned](#10-key-bugs-found-and-lessons-learned)
11. [Registry Paths That Matter](#11-registry-paths-that-matter)
12. [Quick Reference — IPs, Credentials, Paths](#12-quick-reference)

---

## 1. What This Lab Is and Why It Matters

This lab builds a **complete federal-style identity and access management (ICAM) environment**
from scratch using Hyper-V virtual machines. It simulates what a government agency or DoD
contractor must have in place to pass a formal security assessment.

### What Was Built

```
Hyper-V Host (Windows 10/11 Pro)        (10.10.10.1, Lab Internal)
  │
  ├── Lab-OfflineRootCA   (air-gapped, no network adapter)
  │     └── Issues the Root CA certificate
  │         Keeps private key offline — highest security
  │
  ├── Lab-DC01            (10.10.20.10 External + 10.10.10.10 Internal as of v1.4)
  │     ├── Active Directory Domain: lab.local
  │     ├── Enterprise Issuing CA (signs end-user certs)
  │     ├── Certificate Templates (SmartCardLogon, AdminSmartCardLogon)
  │     ├── Smart Card GPO enforcement
  │     ├── OCSP Responder (certificate revocation checking)
  │     └── Audit Policy (Kerberos, Logon, AD CS events)
  │
  └── Lab-Workstation01   (10.10.10.20)
        ├── Joined to lab.local
        ├── Smart card enforcement via GPO
        └── Test workstation for CAC logon (Server 2022 VM)

WO02 — physical Dell laptop  (10.10.20.30, External)
  ├── Windows 11 Pro, domain-joined to lab.local
  ├── Hardware-backed smart-card enrollment (YubiKey 5 NFC)
  ├── Smart-card-required GPO enforced (no password logon)
  ├── 2-second lock-on-removal (ScRemoveOption=1)
  ├── Azure P2S VPN client with EAP-TLS cert auth (same YubiKey)
  └── SCAP scan target — Windows 11 STIG benchmark
```

WO02 is the **physical endpoint** in the lab. The two server VMs (DC01, WS01)
live on the Hyper-V host; WO02 is a real laptop on the lab switch via the
External vSwitch. It's where the user-facing demos happen — lock screen,
PIN entry, lock-on-removal, Azure VPN connect.

### Why the Two-CA Hierarchy?

| CA | Purpose | Security |
|----|---------|---------|
| Root CA (Offline) | Signs the Issuing CA certificate only | Kept powered off — private key never exposed |
| Issuing CA (Online) | Signs end-user and computer certs daily | Online but in a controlled network segment |

If the Issuing CA is ever compromised, you revoke it from the Root CA and replace it.
The Root CA's key stays safe because it was never connected to the network during normal
operations.

---

## 2. The RMF Framework

### What is RMF?

The **Risk Management Framework (RMF)** is the NIST/DoD process for authorizing information
systems to operate. It is defined in:
- **NIST SP 800-37** — RMF for Information Systems
- **NIST SP 800-53** — Security and Privacy Controls (the control catalog)
- **DISA RMF Process Guide** — DoD-specific implementation

### The 7 RMF Steps

```
Step 1 — PREPARE
  Define roles, identify systems, establish risk tolerance

Step 2 — CATEGORIZE
  Classify the system: Low / Moderate / High
  (Based on impact if Confidentiality, Integrity, or Availability is lost)

Step 3 — SELECT
  Choose security controls from NIST SP 800-53
  This lab implements: IA-2, IA-5, AC-2, AC-5, AU-2, AU-9, SC-17

Step 4 — IMPLEMENT
  Actually build and configure the controls
  (What we did in this lab — PKI, smart card, audit policy)

Step 5 — ASSESS
  Test whether the controls actually work
  (SCAP SCC scan, Invoke-LabValidation.ps1)

Step 6 — AUTHORIZE
  AO (Authorizing Official) reviews the risk and signs the ATO
  (Authority to Operate)

Step 7 — MONITOR
  Continuously check that controls stay in place
  (Monitor-PKIHealth.ps1, Set-AuditLogForwarding.ps1)
```

### NIST SP 800-53 Controls Implemented in This Lab

| Control | Name | What We Built |
|---------|------|---------------|
| IA-2 | Identification and Authentication | CAC/PIV smart card logon |
| IA-2(1) | MFA for Privileged Accounts | Admin smart card cert template |
| IA-2(11) | Remote Access MFA | Smart card enforcement GPO |
| IA-5 | Authenticator Management | Certificate templates, enrollment ceremony |
| IA-5(2) | PKI-Based Authentication | Two-tier PKI, OCSP |
| AC-2 | Account Management | AD users, enrollment roles |
| AC-5 | Separation of Duties | Two-person enrollment (RA + Issuer phases) |
| AU-2 | Event Logging | Audit policy (4624, 4768, 4886-4890) |
| AU-9 | Protection of Audit Info | Forwarding to collector via WEF |
| AU-12 | Audit Record Generation | Advanced Audit Policy subcategories |
| SC-17 | PKI Certificates | Full PKI chain, CRL, OCSP |
| CA-7 | Continuous Monitoring | PKI health monitor, alert thresholds |

---

## 3. PKI — How Certificate-Based Authentication Works

### The Chain of Trust

```
Root CA Certificate (self-signed, kept offline)
  │
  └── Signs → Issuing CA Certificate
                │
                └── Signs → User/Computer Certificates
                              (Smart Card Logon cert)
```

Every certificate is "trusted" because it was signed by something already trusted.
Your computer trusts the Root CA certificate (installed in LocalMachine\Root).
Therefore it trusts anything the Issuing CA signed. Therefore it trusts your smart card cert.

### Key Certificate Concepts

**X.509 Certificate Fields That Matter**
```
Subject         : Who this cert is for (CN=Glenn Byron, UPN=labuser@lab.local)
Issuer          : Who signed it (CN=Lab Issuing CA)
NotBefore       : Valid from date
NotAfter        : Expiration date
Subject Alt Name: UPN / email for smart card logon (CRITICAL for CAC)
Enhanced Key Usage (EKU):
  1.3.6.1.4.1.311.20.2.2 = Smart Card Logon
  1.3.6.1.5.5.7.3.2      = Client Authentication
Key Usage       : DigitalSignature, KeyEncipherment
```

**What Makes a Certificate Work for Smart Card Logon**
1. Has EKU = Smart Card Logon (OID 1.3.6.1.4.1.311.20.2.2)
2. Subject Alternative Name includes the user's UPN
3. Issued by a CA trusted by the domain controller
4. Not expired, not revoked
5. CRL or OCSP is reachable at logon time

### Certificate Revocation

When a certificate needs to be invalidated (lost card, terminated employee):

- **CRL (Certificate Revocation List):** A file published periodically listing all revoked
  serial numbers. The DC downloads it on a schedule. If the CRL is unreachable at logon,
  logon fails (fail-closed for security).

- **OCSP (Online Certificate Status Protocol):** Real-time revocation check. The client
  sends the serial number and gets a signed "good" or "revoked" response. Faster and
  more current than CRL.

In this lab: CRL published to `http://pki.lab.local/crl/`, OCSP at `http://pki.lab.local/ocsp`.

---

## 4. Smart Card / CAC / PIV — The Full Chain

### What a CAC/PIV Card Actually Is

A CAC (Common Access Card) or PIV (Personal Identity Verification) card is a smart card
that contains:
- An X.509 certificate (with your identity in the Subject and UPN in the SAN)
- The corresponding **private key** — stored on the chip, never extractable
- A PIN that unlocks the private key for use

The private key never leaves the card. When Windows needs to authenticate you:
1. It sends a random challenge to the card
2. You enter your PIN
3. The card signs the challenge with your private key
4. Windows verifies the signature against your public key (in the certificate)
5. Kerberos ticket is issued — you are logged in

### PIV Slots on a Smart Card

| Slot | Purpose | Algorithm |
|------|---------|-----------|
| 9A | PIV Authentication (logon) | RSA 2048 or ECC P-256 |
| 9C | Digital Signature | RSA 2048 |
| 9D | Key Management (encryption) | RSA 2048 |
| 9E | Card Authentication (physical access) | RSA 2048 |

For Windows logon, Slot 9A is used.

### The Kerberos PKINIT Flow (Smart Card Logon)

```
User inserts card → enters PIN
     │
     ▼
Windows sends AS-REQ to KDC (Domain Controller)
with PKINIT pre-authentication data
(certificate + signed timestamp)
     │
     ▼
KDC validates:
  - Certificate is trusted (chain to Root CA)
  - Certificate is not revoked (CRL/OCSP check)
  - UPN in certificate matches AD account
  - Time skew < 5 minutes (CRITICAL)
     │
     ▼
KDC issues TGT (Ticket Granting Ticket)
Event 4768 logged in Security log
     │
     ▼
User is logged in — no password ever transmitted
```

### Why Time Skew Breaks Smart Card Logon

Kerberos uses timestamps in the authentication packet to prevent replay attacks.
If the client clock and the KDC clock differ by more than **5 minutes (300 seconds)**,
the KDC rejects the authentication.

This is why `w32tm /resync /force` is in every smart card troubleshooting guide.

---

## 5. Active Directory and GPO Enforcement

### Smart Card Enforcement Registry Keys

Two registry paths control smart card enforcement behavior:

**GPO path (what Group Policy writes — what SCAP checks):**
```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
  scforceoption     = 1  (require smart card for interactive logon)
  ScRemoveOption    = 1  (lock workstation when card removed)
                    = 2  (force logoff when card removed)
  InactivityTimeoutSecs = 900  (lock after 15 min idle)
```

**Legacy Winlogon path (also read by Windows logon process):**
```
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon
  scforceoption     = 1
  ScRemoveOption    = 1
```

**CRITICAL LESSON:** Setting `scforceoption=1` on a Domain Controller locks out ALL
password-based login — console, PowerShell Direct, RDP — everything.
NEVER set smart card enforcement on a DC. Only on workstations.

### GPO Linking — Where It Applies

GPO is linked to an **Organizational Unit (OU)**, not the whole domain by default.
In this lab, `Build-CA-GPO.ps1` links the "SmartCard Policy" GPO to:
`OU=SmartCard-Pilot,DC=lab,DC=local`

This means ONLY computers in that OU receive the policy. The DC is NOT in that OU.
This is intentional — smart card enforcement on the DC would lock out administrators.

To apply to the domain root (all computers): link the GPO to `DC=lab,DC=local`.
But always exclude DCs with a **WMI filter** or **security filtering**.

### Separation of Duties in Enrollment (AC-5)

The `New-TokenEnrollment.ps1` script enforces two-person control:

```
Phase 1 — Registration Authority (RA)
  - Run by one person (the RA)
  - Verifies the user's identity (checks ID, validates attributes)
  - Records that identity verification occurred

Phase 2 — Card Issuer
  - MUST be run by a DIFFERENT account than Phase 1
  - Script checks who ran Phase 1 and blocks the same account
  - Actually enrolls the certificate and provisions the card
```

This prevents a single person from both approving and issuing a credential —
a core separation of duties requirement (NIST AC-5, DoD CAC policy).

---

## 6. STIG Compliance

### What is a STIG?

A **Security Technical Implementation Guide (STIG)** is a DoD-published configuration
standard for a specific technology. STIGs tell you exactly how a system must be configured
to be considered secure for DoD use.

STIGs are published by DISA (Defense Information Systems Agency) at:
`https://public.cyber.mil/stigs/`

### STIG Structure

Each STIG contains **rules (checks)**. Each rule has:

```
Rule ID:     V-254285 (vulnerability ID)
STIG ID:     WN22-CC-000030 (check ID for this specific STIG)
Severity:    CAT I / CAT II / CAT III
  CAT I   = Critical (must fix — system is at unacceptable risk)
  CAT II  = High (should fix — significant risk)
  CAT III = Medium (fix when possible — moderate risk)

Finding:     What the checker looks for
Fix:         How to remediate
Check:       How to verify compliance
```

### STIG Findings Status

| Status | Meaning |
|--------|---------|
| Open | Check failed — control not in place |
| Not a Finding | Check passed — control is in place |
| Not Applicable | Rule does not apply to this system |
| Not Reviewed | Manual check — automated tool cannot verify |

### What the Windows Server 2022 STIG Checks

Key categories relevant to this lab:

**IA Controls (Identity and Authentication)**
- Smart card requirement for privileged accounts
- Password complexity and history
- Account lockout settings

**AU Controls (Audit)**
- Advanced Audit Policy subcategories (Logon, Kerberos, AD CS)
- Security log size (minimum 1GB for servers)
- Log protection (cannot be cleared without audit event)

**SC Controls (System and Communications)**
- PKI certificate validation
- FIPS 140 mode
- TLS configuration

**AC Controls (Access Control)**
- User Rights Assignments (who can log on locally, via network, etc.)
- Restricted Groups
- Anonymous access restrictions

---

## 7. SCAP and SCC — The Scanning Tools

### What is SCAP?

**Security Content Automation Protocol (SCAP)** is a NIST standard for expressing
security checks in a machine-readable format. A SCAP bundle contains:

```
XCCDF (Extensible Configuration Checklist Description Format)
  └── The list of rules and their relationships

OVAL (Open Vulnerability and Assessment Language)
  └── The actual checks (registry values, file contents, WMI queries)

CPE (Common Platform Enumeration)
  └── Which platforms this content applies to

OCIL (Open Checklist Interactive Language)
  └── Manual questions that can't be automated
```

### What is DISA SCC?

**SCAP Compliance Checker (SCC)** is DISA's free tool that:
1. Takes SCAP content (STIG benchmarks)
2. Runs the automated checks against the local machine or remote hosts
3. Produces HTML/XML/text reports showing pass/fail for each rule
4. Generates ARF (Asset Reporting Format) output for feeding into eMASS

Download from: `https://public.cyber.mil/stigs/scap/`

### SCC Scan Process

```
1. Install SCC on the target machine (or scanning machine for remote)

2. Open SCC → Select Content
   - Choose the applicable STIG benchmark
   - If OS version doesn't match CPE exactly:
     → Check "Run content regardless of applicability"
     (Windows Server 2025 uses Windows Server 2022 STIG until 2025 STIG is published)

3. Select Profile
   MAC-1_Classified  = Most restrictive (classified systems)
   MAC-2_Sensitive   = Standard DoD
   MAC-3_Public      = Least restrictive

4. Click Start Scan
   - Automated OVAL checks run (~5-15 minutes)
   - Manual questions marked "Not Reviewed"

5. Review Results
   - HTML report opens in browser
   - XML results for eMASS import
   - ARF file for automated processing
```

### Understanding SCC Output

```
SCAP Score: 42 / 100 (Before MFA)
  │
  ├── 12 Open Findings (CAT I + CAT II)
  │     ├── V-254318: Smart card not required (CAT I) ← Before MFA
  │     ├── V-254285: Audit policy not configured (CAT II)
  │     └── ...
  │
  ├── 67 Not a Finding (passing)
  │
  └── 21 Not Reviewed (manual checks)

After MFA enrollment:
SCAP Score: 78 / 100
  │
  ├── 3 Open Findings (residual risk)
  └── Smart card findings now PASS
```

### CPE Platform Check

SCAP content embeds CPE (platform identifiers) that define which OS versions it applies to.
Windows Server 2022 STIG has CPE for WS2022 only. Running it on WS2025 fails the CPE check.

**Fix:** Check "Run content regardless of applicability" in SCC Content Details panel.
This overrides the platform check and runs the rules anyway. For a new OS without its
own STIG, this is the correct approach.

---

## 8. Vulnerability Scanning vs. Compliance Scanning

These are different activities that are often confused:

| | Compliance Scanning | Vulnerability Scanning |
|---|---|---|
| **Tool** | DISA SCC, STIG Viewer | Nessus, Tenable.sc, OpenVAS |
| **What it checks** | Is the system configured per the STIG? | Are there known CVEs / exploitable conditions? |
| **Pass/Fail basis** | DoD configuration standards | CVSS score / CVE database |
| **Output format** | XCCDF results, ARF, CKL | Nessus .nessus file, CSV |
| **Used for** | ATO/RMF authorization | Patch management, vulnerability management |
| **Frequency** | Before/after changes, quarterly | Weekly / continuous |

### How They Relate in RMF

```
RMF Step 4 (Implement) → Configure per STIG
RMF Step 5 (Assess)    → SCAP scan (compliance) + Vuln scan
                          Both feed into the Security Assessment Report (SAR)
RMF Step 6 (Authorize) → AO reviews SAR, accepts residual risk, signs ATO
```

### Plan of Action and Milestones (POA&M)

Any finding that is Open (failing) goes into the **POA&M**:
- Lists each finding with risk level
- Assigns a responsible person
- Sets a remediation milestone date
- CAT I: must be fixed before ATO or have accepted exception
- CAT II: 90-day remediation window
- CAT III: 180-day remediation window

---

## 9. Before/After MFA Scan Methodology

### Why Run Two Scans?

The DoD RMF process requires demonstrating that security controls **work** — not just
that they're configured. For smart card enforcement, the methodology is:

```
BEFORE scan → shows the baseline (many IA-2 controls failing)
  ↓
Smart card enrollment / enforcement applied
  ↓
AFTER scan → shows improvement (IA-2 controls now passing)
```

The delta between scans is the **evidence** that your control implementation worked.
This goes into the Security Assessment Report (SAR) and the ATO package.

### What the Before Scan Shows (Expected Failures)

On a Windows Server system BEFORE smart card enforcement:
- **V-254318**: Interactive logon does not require smart card → **Open (CAT II)**
- **V-254321**: Smart card removal behavior not configured → **Open (CAT III)**
- **V-254244**: No PIV/CAC certificate in trust store → **Open (CAT I)**
- Audit policy subcategories may not be configured → Multiple Opens

### What the After Scan Shows (Expected Passes)

After completing this lab:
- Smart card required (scforceoption=1) → **Not a Finding**
- Card removal locks workstation → **Not a Finding**
- Root CA and Issuing CA in trust store → **Not a Finding**
- Audit policy configured → **Not a Finding**
- Event 4768 (Kerberos TGT) appearing in Security log → **Not a Finding**

### Stage-Reports.ps1

The `Stage-Reports.ps1` script in `Lab-Kit\05-Compliance\` organizes the scan output:
- Copies SCC XML/HTML results into a labeled folder (`Before-MFA`, `After-MFA`)
- Generates a comparison summary
- Packages everything for the ATO submission package

---

## 10. Key Bugs Found and Lessons Learned

### Lesson 1: UTF-8 BOM Is Required for PowerShell 5.1

PowerShell 5.1 (the default on Windows) reads `.ps1` files as Windows-1252 (legacy
encoding) unless the file has a **UTF-8 BOM** (byte order mark: `EF BB BF`) at the
start. If your script contains em dashes (`—`), box-drawing characters, or other
non-ASCII characters without BOM, PowerShell misreads them and throws parse errors.

**Fix:** Always save PowerShell scripts with UTF-8 BOM encoding. To add BOM to existing files:
```powershell
Get-ChildItem -Path "C:\Scripts" -Recurse -Filter *.ps1 | ForEach-Object {
    $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
    if ($bytes[0] -ne 0xEF) {
        [System.IO.File]::WriteAllBytes($_.FullName, [byte[]](0xEF,0xBB,0xBF) + $bytes)
    }
}
```
**Note:** `[System.IO.File]::WriteAllText()` strips the BOM. Always use `WriteAllBytes`
when you need to preserve or add a BOM.

---

### Lesson 2: Install-AdcsCertificationAuthority Needs a Network Stack

Even for a StandaloneRootCA with no AD dependency, `Install-AdcsCertificationAuthority`
fails with ERROR_NETWORK_UNREACHABLE (0x800704cf) on a VM with no network adapters.
Windows AD CS requires an active network stack during setup.

**Fix:** Attach a Hyper-V **Private** switch (no external connectivity) before running
the ceremony. Remove it after. Type `OVERRIDE` at the air-gap check prompt.

---

### Lesson 3: Get-NetAdapter Returns a Single Object, Not an Array

Under `Set-StrictMode -Version Latest`, calling `.Count` on a single object (not an
array) throws `PropertyNotFoundStrict`. `Get-NetAdapter` returns one object when only
one adapter exists.

**Fix:** Wrap all cmdlet results in `@()` when you need `.Count`:
```powershell
$adapters = @(Get-NetAdapter)
if ($adapters.Count -eq 0) { ... }
```

---

### Lesson 4: Copy-Item -ToSession Needs the Directory to Exist Inside the VM First

When using `Copy-Item -ToSession` to copy files into a VM via PowerShell Direct,
the destination directory must exist **inside the VM**. Running `New-Item` without
`Invoke-Command` creates the folder on the **host**, not the VM.

```powershell
# WRONG — creates C:\Scripts on the HOST
New-Item -ItemType Directory -Path "C:\Scripts" -Force

# CORRECT — creates C:\Scripts inside the VM
Invoke-Command -Session $s -ScriptBlock {
    New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null
}
```

---

### Lesson 5: Copy-CertificateTemplate Does Not Exist in PSPKI

The PSPKI PowerShell module has no `Copy-CertificateTemplate` cmdlet in any version.
The correct way to duplicate a certificate template in PowerShell is:
```powershell
# Get source template with explicit attribute list
$src = Get-ADObject -Identity "CN=$SourceTemplate,$containerDN" -Properties flags,revision,...
# Create new template using AD module
New-ADObject -Name $NewName -Type 'pKICertificateTemplate' -Path $containerDN -OtherAttributes $attrs
```
**Note:** `Get-ADObject -Properties *` returns synthetic properties (Created, Modified, etc.)
that break `-OtherAttributes`. Always use an explicit property list.

---

### Lesson 6: scforceoption=1 on a DC = Complete Lockout

Setting `scforceoption=1` in the Policies\System registry path on a **Domain Controller**
enforces smart card for ALL authentication paths — including Hyper-V console, PowerShell
Direct, and RDP. There is no password fallback.

**Rule:** NEVER set smart card enforcement on a DC.
Only set it on **workstations** where end users log in.
The DC must retain password access as a break-glass path.

**Recovery if locked out:**
```
METHOD 1: DSRM
  Stop-VM; Start-VM → spam F8 → Directory Services Repair Mode
  Login: .\Administrator / <DSRM password>
  Remove scforceoption from registry

METHOD 2: Offline VHDX edit
  Stop-VM -TurnOff → Mount-VHD → reg load → Remove-ItemProperty → reg unload → Dismount-VHD → Start-VM
```

---

### Lesson 7: Validation Registry Path vs. Enforcement Path

Two different registry paths — different purposes:

| Path | Used For |
|------|---------|
| `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` | GPO-written settings — what SCAP/SCC checks |
| `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon` | Legacy direct settings |

If your validation script reads from Policies\System and you set values in Winlogon,
the scan will show FAIL even though the setting appears configured. Always set values
in the path the tool actually reads.

---

### Lesson 8: Kerberos Time Skew Is a Real Failure Mode

Kerberos authentication fails if client and KDC clocks differ by more than **5 minutes**.
This is not just a theoretical concern — it caused actual PowerShell Direct failures
in this lab.

Common causes in Hyper-V labs:
- Hyper-V IC Time Synchronization syncs VM clock to host's local time
- If VM timezone doesn't match host timezone, the UTC offset is wrong
- DC shows 7:03 AM (local Eastern) but timezone is UTC → DC thinks UTC is 7:03, actual UTC is 11:03

**Fix:** Ensure DC timezone matches the Hyper-V host timezone.
**Check:** `[System.DateTime]::UtcNow` on both host and DC should show the same time (within seconds).

---

### Lesson 9: DomainController.CurrentTime Returns UTC with Kind=Unspecified

In .NET, `[System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().FindDomainController().CurrentTime`
returns the DC's current time from LDAP GeneralizedTime (which is UTC), BUT the .NET
DateTime object has `Kind = Unspecified`. Calling `.ToUniversalTime()` on an Unspecified
DateTime assumes it is Local time and adds the UTC offset — converting it WRONG.

```powershell
# WRONG — doubles the timezone offset
$skew = ([datetime]::UtcNow - $domainTime.ToUniversalTime()).TotalSeconds

# CORRECT — mark it as UTC before using it
$domainTimeUtc = [DateTime]::SpecifyKind($domainTime, [DateTimeKind]::Utc)
$skew = ([datetime]::UtcNow - $domainTimeUtc).TotalSeconds
```

---

### Lesson 10: Hyper-V Enhanced Session vs. Basic Session

| Mode | File Transfer | Clipboard | Resolution |
|------|--------------|-----------|------------|
| Basic Session | Not supported (no \\tsclient) | Limited | Low |
| Enhanced Session | \\tsclient\C works | Full | Scalable |

Enhanced Session uses RDP internally. Drive redirection (`\\tsclient\C`) only works
in Enhanced Session. To use it: View → Enhanced Session → Local Resources → Drives.

If Enhanced Session is unavailable, use the VHDX pass-through method:
create a small VHDX, copy files to it on the host, attach it to the VM as a second disk.

---

### Lesson 11: auditpol Subcategory Regex Trap

The output of `auditpol /get /subcategory:"Logon"` looks like:
```
System audit policy
Category/Subcategory          Setting
Logon/Logoff
  Logon                       Success and Failure
```

If you search for lines matching "Logon", you get `Logon/Logoff` FIRST — which has
no setting text on it. The check returns "No Auditing" even when audit is configured.

**Fix:** Require leading whitespace in the match to skip category headers:
```powershell
$line = $out | Where-Object { $_ -match "^\s+$([regex]::Escape($Subcategory))" } | Select-Object -First 1
```

---

## 11. Registry Paths That Matter

### Smart Card Enforcement
```
HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System
  scforceoption     REG_DWORD  1 = require smart card (WORKSTATION ONLY)
  ScRemoveOption    REG_DWORD  1 = lock on removal, 2 = logoff on removal
  InactivityTimeoutSecs REG_DWORD  900 = 15-minute idle lock

HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon
  scforceoption     REG_DWORD  1 (legacy path, also enforced)
  ScRemoveOption    REG_DWORD  1
```

### Audit Policy (checked via auditpol, not registry)
```powershell
auditpol /set /subcategory:"Logon" /success:enable /failure:enable
auditpol /set /subcategory:"Kerberos Authentication Service" /success:enable /failure:enable
auditpol /set /subcategory:"Certification Services" /success:enable /failure:enable
```

### Certificate Stores
```
Cert:\LocalMachine\Root     = Trusted Root CAs (Root CA cert goes here)
Cert:\LocalMachine\CA       = Intermediate/Issuing CAs (Issuing CA cert goes here)
Cert:\CurrentUser\My        = User's personal certs (smart card logon cert goes here)
```

### Time Synchronization
```powershell
w32tm /query /status          # Check current time source and offset
w32tm /resync /force          # Force immediate sync
Get-Service W32Time            # Service name is W32Time, not w32tm
```

---

## 12. Quick Reference

### Lab Network

| VM | IP | Role |
|----|----|----|
| Lab-DC01 | 10.10.10.10 | DC, DNS, Issuing CA, OCSP |
| Lab-Workstation01 | 10.10.10.20 | Test workstation |
| Lab-OfflineRootCA | No IP (air-gapped) | Root CA only |
| Hyper-V Host (LabInternal) | 10.10.10.1 | Host management interface |

### Credentials

| Account | Password | Notes |
|---------|---------|-------|
| All local Administrator | `<LAB-ADMIN-PASSWORD>` | Set during Windows install |
| LAB\Administrator | `<LAB-ADMIN-PASSWORD>` | Domain admin |
| DSRM (.\Administrator) | `<LAB-ADMIN-PASSWORD>` | DC break-glass only |

### File Locations

| Item | Path |
|------|------|
| Lab kit (host) | `C:\path\to\CAC-program\` |
| Downloaded tools (host) | `C:\FedCompliance-Tools\` |
| Scripts on DC | `C:\Scripts\` |
| SCC install (DC) | `C:\Program Files\SCAP Compliance Checker 5.10.2\` |
| SCC results (DC) | `C:\Users\Administrator\SCC\Sessions\` |
| CA transfer files (host) | `C:\CA-Transfer\OfflineCA-Export\` |
| VM disks (host) | `C:\HyperV-Lab\` |

### Key PowerShell Commands

```powershell
# Check domain health
nltest /dclist:lab.local
dcdiag /test:replications

# Check PKI
certutil -ping                           # Test CA connectivity
certutil -URL <cert-file>                # Test CRL/OCSP URLs from a cert
certutil -verify -urlfetch <cert-file>   # Full chain and revocation check

# Check smart card
Get-Service SCardSvr                     # Smart card service
Get-WmiObject -Namespace root\SmartCardReader -Class MSSmartCard_Reader  # Readers

# Check Kerberos
klist                                    # Current Kerberos tickets
klist purge                              # Clear ticket cache (force re-auth)

# Check audit policy
auditpol /get /category:*               # All audit categories
auditpol /get /subcategory:"Logon"      # Specific subcategory

# Check time
w32tm /query /status                    # NTP sync status
[System.DateTime]::UtcNow              # Current UTC time

# Check GPO
gpresult /r                             # Applied GPOs
gpupdate /force                         # Force policy refresh (workstation only)
```

### Event IDs to Know

| Event ID | Log | Meaning |
|----------|-----|---------|
| 4624 | Security | Successful logon |
| 4625 | Security | Failed logon |
| 4648 | Security | Explicit credential logon |
| 4768 | Security | Kerberos TGT requested (smart card logon shows cert info here) |
| 4769 | Security | Kerberos service ticket requested |
| 4771 | Security | Kerberos pre-auth failed (wrong PIN, expired cert, time skew) |
| 4776 | Security | NTLM authentication |
| 4886 | Security | Certificate requested from CA |
| 4887 | Security | Certificate issued by CA |
| 4888 | Security | Certificate request denied |
| 4889 | Security | Certificate revoked |
| 4890 | Security | CA settings changed |

---

## Summary

This lab built a complete federal ICAM environment and walked through the full RMF
assess phase. The key takeaways:

1. **PKI is the foundation** — without a trusted certificate chain, smart card logon
   cannot work. The two-tier CA hierarchy (offline root, online issuing) is the
   DoD standard and should not be shortcut.

2. **STIG compliance is measured, not assumed** — running SCAP SCC before and afte