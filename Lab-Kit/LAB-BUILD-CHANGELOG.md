# CAC Lab Kit — Change Log

> **This file is sanitized for public distribution.**
> Real lab passwords appear as `<LAB-ADMIN-PASSWORD>`, `<LAB-LABTECH-PASSWORD>`, etc.
> See `.scrub-patterns.example.json` at the repo root for the full pattern list.

All changes made after the initial commit are recorded here.
Copy these fixes to your main machine files when syncing.

---

## 2026-05-26 — Session 1 (Glenn Byron)

### Tools-Kit Scripts — UTF-8 BOM Fix (all 4 files)

**Files:**
- `Tools-Kit\Get-LabTools.ps1`
- `Tools-Kit\Download-FedCompliance-Kit.ps1`
- `Tools-Kit\Download-OfflineCA-Kit.ps1`
- `Tools-Kit\Download-IssuingCA-Kit.ps1`

**Problem:** Scripts were saved without UTF-8 BOM. PowerShell 5.1 reads them as
Windows-1252, causing em dashes (UTF-8: E2 80 94) to be misread as right double-quote
(0x94), which terminates strings mid-parse and throws "missing string terminator" errors.

**Fix:** Prepend UTF-8 BOM bytes (EF BB BF) to each file:
```powershell
$file = "path\to\script.ps1"
$bytes = [System.IO.File]::ReadAllBytes($file)
if ($bytes[0] -ne 0xEF) {
    [System.IO.File]::WriteAllBytes($file, [byte[]](0xEF,0xBB,0xBF) + $bytes)
}
```

---

### `Tools-Kit\Download-OfflineCA-Kit.ps1` — Variable Expansion Bug

**Problem:** `Signature="$Windows NT$"` inside a `@"..."@` here-string caused PowerShell
to expand `$Windows` as a variable (undefined), throwing a runtime error.

**Fix:** Escaped to `` Signature="`$Windows NT`$" ``

---

### `Tools-Kit\Download-IssuingCA-Kit.ps1` — Two Runtime Bugs

**Bug 1:** Logging helper (`Write-Step`) called `Add-Content` to a log file before the
staging directory existed, throwing "path not found."

**Fix:** Added staging directory creation before the first `Write-Step` call:
```powershell
if (-not (Test-Path $StagingPath)) {
    New-Item -ItemType Directory -Path $StagingPath -Force | Out-Null
}
```

**Bug 2:** `Get-WindowsFeature` is a Server-only cmdlet — fails on Windows 11 client.

**Fix:** Check `ProductType` first; skip on workstation (type = 1):
```powershell
$osProductType = (Get-CimInstance -ClassName Win32_OperatingSystem).ProductType
if ($osProductType -eq 1) {
    Write-Warn "Skipping feature check — this machine is a Windows client (not Server)."
} else {
    # ... feature check block
}
```

---

### `Lab-Kit\01-HyperV-Host\Set-VMPostConfig.ps1` — `.Count` on Single Object

**Problem:** `$adapters = Get-NetAdapter` followed by `$adapters.Count` throws
`PropertyNotFoundStrict` under `Set-StrictMode -Version Latest` when only one adapter
is present (single object has no `.Count` property — only arrays do).

**Fix:** Wrap in `@()` to force array:
```powershell
$adapters = @(Get-NetAdapter)
if ($adapters.Count -eq 0) { ... }
```

---

### `Lab-Kit\02-OfflineRootCA\Initialize-OfflineRootCA.ps1` — UTF-8 BOM Fix

**Problem:** Same BOM issue as Tools-Kit scripts — parse errors on em dashes and
box-drawing characters.

**Fix:** Same BOM prepend fix as above. Apply on the Hyper-V host before transferring
to the VM.

---

### `Lab-Kit\02-OfflineRootCA\Initialize-OfflineRootCA.ps1` — Loopback Adapter Required

**Problem:** `Install-AdcsCertificationAuthority` fails with `ERROR_NETWORK_UNREACHABLE
(0x800704cf)` on a VM with no network adapters, even for a StandaloneRootCA that has
no AD dependency. Windows AD CS requires an active network stack during setup.

**Fix:** Attach a Hyper-V Private switch before running the ceremony, remove after:
```powershell
# Before running (on Hyper-V host):
New-VMSwitch -Name "OfflineCA-Loopback" -SwitchType Private
Add-VMNetworkAdapter -VMName "Lab-OfflineRootCA" -SwitchName "OfflineCA-Loopback"

# After ceremony completes (on Hyper-V host):
Get-VMNetworkAdapter -VMName "Lab-OfflineRootCA" |
    Where-Object { $_.SwitchName -eq "OfflineCA-Loopback" } |
    Remove-VMNetworkAdapter
```
Type `OVERRIDE` at Step 1 air-gap check — the Private switch has no external connectivity.

**Recovery if Step 4 fails "already installed":** Uninstall feature and reboot:
```powershell
Uninstall-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
Restart-Computer -Force
```

---

### `Lab-Kit\01-HyperV-Host\README.md` — Major Rewrites

- **Step 2:** Replaced VHDX-based answer drive approach with ISO-based approach using
  IMAPI2 C# IsoWriter. Root cause: Windows Setup windowsPE pass only scans removable
  media (DVD/USB) for answer files — SCSI VHDXs are hard disks and are ignored.
  Filename must be `autounattend.xml` (not `unattend.xml`) on removable media.
- **Step 3:** Added "open VM window BEFORE starting" and "spam Space" boot instructions.
  Added white screen explanation (WinPE loading, wait ~2 min). Added manual install
  click-through steps as the reliable fallback.
- **Step 4:** Fixed `Copy-Item -ToSession` transfer — must use `Invoke-Command` to
  create `C:\Scripts` inside the VM first. Running `New-Item` bare creates the folder
  on the Hyper-V host, not inside the VM.

---

### `Lab-Kit\04-Workstation` — Phase 7 Fixes

**Bug 1 — Lab-Workstation01 APIPA Address After Domain Join**

**Problem:** Lab-Workstation01 had DHCP Enabled and an APIPA address (169.254.x.x)
after joining. `Set-VMPostConfig.ps1` was supposed to set the static IP but it didn't
persist. `Add-Computer` failed with "domain does not exist or could not be contacted."

**Fix:** Set static IP and DNS manually with netsh before domain join (same fix as DC):
```powershell
netsh interface ipv4 set address name="Ethernet" static 10.10.10.20 255.255.255.0 10.10.10.1
netsh interface ipv4 set dns name="Ethernet" static 10.10.10.10
```
Note: `netsh` shows "DNS server is incorrect or does not exist" warning — this is a
connectivity validation warning only. The DNS setting is still applied.

**Bug 2 — `Enforce-SmartCard.ps1` Is a DC Script, Not a Workstation Script**

**Problem:** `Lab-Kit\04-Workstation\README.md` says to run `Enforce-SmartCard.ps1`
on Lab-Workstation01. The script uses `Import-Module GroupPolicy` and
`Set-GPRegistryValue` — these are DC/RSAT cmdlets. Running it on a workstation
would fail.

**Fix:** `Build-CA-GPO.ps1` (already run in Phase 6) creates and links the smart card
enforcement GPO (`scforceoption=1`, `ScRemoveOption=1`) on the domain. After the
workstation joins the domain, run `gpupdate /force` to pull the GPO — no separate
`Enforce-SmartCard.ps1` execution needed on the workstation.

---

### `Lab-Kit\05-Compliance\Invoke-LabValidation.ps1` — Kerberos Time Skew Bug

**Problem:** The skew check always reports ~14400s (4 hours) regardless of actual clock
sync status. Root cause: `DomainController.CurrentTime` returns UTC (from LDAP
GeneralizedTime), but `(Get-Date)` returns local time. Subtraction without timezone
conversion produces the local timezone offset as a fake skew.

**Fix:** Compare both values in UTC:
```powershell
# Before (wrong):
$skewSec = [math]::Abs(((Get-Date) - $domainTime).TotalSeconds)

# After (correct):
$skewSec = [math]::Abs(([datetime]::UtcNow - $domainTime.ToUniversalTime()).TotalSeconds)
```

Apply patch inside the DC if the old version was already copied:
```powershell
$file = "C:\Scripts\05-Compliance\Invoke-LabValidation.ps1"
$content = [System.IO.File]::ReadAllText($file)
$content = $content -replace '\(\(Get-Date\) - \$domainTime\)\.TotalSeconds', '([datetime]::UtcNow - $domainTime.ToUniversalTime()).TotalSeconds'
[System.IO.File]::WriteAllText($file, $content)
```

---

### `Lab-Kit\03-DomainController` — scforceoption=1 LOCKS OUT Lab-DC01 COMPLETELY

**Problem:** Setting `scforceoption=1` in
`HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` on a Domain Controller
enforces "Interactive logon: Require smart card" for ALL authentication paths — including
the Hyper-V Basic Session console, PowerShell Direct, and RDP. Once set, no password-based
login is possible. The console shows "You must use Windows Hello or a smart card to sign in"
with no password field and no way to recover without DSRM or offline VHDX registry edit.

**Root cause:** The Invoke-LabValidation.ps1 Layer 4 checks test for `scforceoption=1` and
report FAIL if it is not set. To make the validation pass, we set the value in the registry —
which immediately locked out the DC.

**Rule:** NEVER SET scforceoption=1 ON Lab-DC01.
Smart card enforcement belongs on Lab-Workstation01 only.
The DC must retain password "break glass" access for administration.

**Recovery — Method 1 (DSRM):**
```
Stop-VM "Lab-DC01"; Start-VM "Lab-DC01" — spam F8 — Directory Services Repair Mode
Username: .\Administrator  Password: <LAB-ADMIN-PASSWORD>
Remove-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System" -Name scforceoption -Force
Restart-Computer -Force
```

**Recovery — Method 2 (Offline VHDX registry edit — use when F8 fails):**
```powershell
Stop-VM -Name "Lab-DC01" -TurnOff -Confirm:$false
while ((Get-VM "Lab-DC01").State -ne "Off") { Start-Sleep 1 }
$vhdPath = (Get-VM "Lab-DC01" | Get-VMHardDiskDrive | Select-Object -First 1).Path
Mount-VHD -Path $vhdPath
$diskNum = (Get-VHD -Path $vhdPath).DiskNumber
$part = Get-Partition -DiskNumber $diskNum | Where-Object { $_.Size -gt 5GB } |
    Sort-Object Size -Descending | Select-Object -First 1
if (!$part.DriveLetter -or $part.DriveLetter -eq [char]0) {
    $part | Add-PartitionAccessPath -AssignDriveLetter; Start-Sleep 2
    $part = Get-Partition -DiskNumber $diskNum -PartitionNumber $part.PartitionNumber
}
$dl = $part.DriveLetter
reg load "HKLM\TempDC" "${dl}:\Windows\System32\config\SOFTWARE"
Remove-ItemProperty "HKLM:\TempDC\Microsoft\Windows\CurrentVersion\Policies\System" -Name "scforceoption" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty "HKLM:\TempDC\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "scforceoption" -Force -ErrorAction SilentlyContinue
[GC]::Collect(); [GC]::WaitForPendingFinalizers()
reg unload "HKLM\TempDC"
Dismount-VHD -Path $vhdPath
Start-VM -Name "Lab-DC01"
```

**Validation note:** The Invoke-LabValidation.ps1 Layer 4 check for `scforceoption` will
show FAIL on Lab-DC01. This is acceptable and expected — the DC intentionally does not
enforce smart card at the registry level. Smart card enforcement is applied to
Lab-Workstation01 only. Accept this FAIL in the DC validation report.

---

### `Lab-Kit\05-Compliance\Invoke-LabValidation.ps1` — Two Validation Logic Bugs

**Bug 1 — Wrong registry path for GPO/smart card checks (Layer 4)**

**Problem:** Layer 4 checks (`scforceoption`, `ScRemoveOption`, `InactivityTimeoutSecs`) read
from `HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` (the GPO policies
path). Manual fixes were being applied to `HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`
(the legacy Winlogon path). These are different registry hive branches — values set in
Winlogon are invisible to the validation checks.

**Fix:** Set values in the correct path that the script reads:
```powershell
$p = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
Set-ItemProperty -Path $p -Name "scforceoption"         -Value 1   -Type DWord -Force
Set-ItemProperty -Path $p -Name "ScRemoveOption"        -Value 1   -Type DWord -Force
Set-ItemProperty -Path $p -Name "InactivityTimeoutSecs" -Value 900 -Type DWord -Force
```

**Bug 2 — Audit subcategory regex matches category header, not subcategory line**

**Problem:** `auditpol /get /subcategory:"Logon"` output has `Logon/Logoff` (category header)
on one line before `  Logon   Success and Failure` (subcategory line). The regex
`$_ -match $Subcategory` matched the category header line first (via `Select-Object -First 1`),
which contains no setting — so the check always reported "No Auditing" even when audit
was correctly configured.

**Fix:** Require leading whitespace so the pattern only matches subcategory lines:
```powershell
# Before (wrong — matches category header "Logon/Logoff" first):
$line = $out | Where-Object { $_ -match $Subcategory } | Select-Object -First 1

# After (correct — matches subcategory line "  Logon   Success and Failure"):
$line = $out | Where-Object { $_ -match "^\s+$([regex]::Escape($Subcategory))" } | Select-Object -First 1
```

**Known false positives after all fixes (acceptable for isolated lab):**
- **Time skew ~14400s** — Hyper-V VM IC Time Sync sets VM clock to host local time; DC
  timezone is UTC. `DomainController.CurrentTime` (LDAP GeneralizedTime) is UTC; host is
  UTC-4 (Eastern). The 14400s (~4h) is the timezone offset, not a real skew. Kerberos
  actually works (4768 TGT requests visible in Security log).
- **9 expired certs** — Pre-installed Windows built-in root CAs (Microsoft, VeriSign, etc.)
  in `LocalMachine\Root` and `LocalMachine\CA`. Not lab PKI certs. Not fixable/relevant.

After both fixes: 16 PASS, 6 WARN, 2 FAIL (both false positives). Environment is ready
for SCAP SCC scanning.

---

### `Lab-Kit\05-Compliance\Invoke-LabValidation.ps1` and `Stage-Reports.ps1` — UTF-8 BOM Fix

**Problem:** Same BOM issue as all other scripts — em dashes in string literals cause
parse errors (`AmpersandNotAllowed`, `Missing string terminator`) when PowerShell 5.1
reads the file as Windows-1252.

**Fix:** Added UTF-8 BOM (EF BB BF) to both files on the Hyper-V host. Apply the
same fix inside Lab-DC01 before running if the file was copied before this fix:
```powershell
$file = "C:\Scripts\05-Compliance\Invoke-LabValidation.ps1"
$bytes = [System.IO.File]::ReadAllBytes($file)
if ($bytes[0] -ne 0xEF) {
    [System.IO.File]::WriteAllBytes($file, [byte[]](0xEF,0xBB,0xBF) + $bytes)
}
```

---

### `Lab-Kit\START-HERE.md` — Phase 2 and Phase 3 Fixes

- **Phase 2:** Fixed broken `& 'cd .\Tools-Kit\` syntax to proper `cd` + script call.
- **Phase 3:** Added boot sequence instructions (open window first, spam Space, white
  screen wait). Fixed all three `Copy-Item` blocks to use `Invoke-Command` for creating
  `C:\Scripts` inside the VM. Changed relative script paths to full absolute paths.

---

### `Lab-Kit\03-DomainController\New-CertificateTemplates.ps1` — Two Bugs Fixed

**Bug 1 — PSPKI Module Not Available on DC**

**Problem:** Lab-DC01 uses the LabInternal switch (no internet), so `Install-Module` fails
inside the VM and the script fell back to printing manual steps.

**Fix:** Download PSPKI on the Hyper-V host, copy into the VM via PowerShell Direct:
```powershell
Save-Module -Name PSPKI -Path "C:\Temp\PSModules" -Repository PSGallery -Force

$cred = Get-Credential   # LAB\Administrator / <LAB-ADMIN-PASSWORD>
$s = New-PSSession -VMName "Lab-DC01" -Credential $cred
Invoke-Command -Session $s -ScriptBlock {
    New-Item -ItemType Directory -Path "C:\Program Files\WindowsPowerShell\Modules\PSPKI" -Force | Out-Null
}
Copy-Item -Path "C:\Temp\PSModules\PSPKI" `
          -ToSession $s `
          -Destination "C:\Program Files\WindowsPowerShell\Modules\" -Recurse -Force
Remove-PSSession $s
```

**Bug 2 — `Copy-CertificateTemplate` Does Not Exist in Any PSPKI Version**

**Problem:** The script called `$sourceTemplate | Copy-CertificateTemplate -Name ...` to
duplicate the User base template. `Copy-CertificateTemplate` is not a real PSPKI cmdlet —
it does not exist in any version of the module. This caused `CommandNotFoundException`
immediately after PSPKI loaded successfully.

**First fix attempt:** Replaced with raw ADSI `DirectorySearcher` + `$newEntry.SetInfo()`.
This failed with `"The specified directory service attribute or value does not exist"` because
DirectorySearcher returns byte array attributes (pKIKeyUsage, pKIExpirationPeriod,
pKIOverlapPeriod) in a format that ADSI cannot reliably put back on a new object.

**Final fix:** Replaced with `Get-ADObject -Properties *` + `New-ADObject -OtherAttributes`.
The AD PowerShell module (available on Lab-DC01 as a DC) handles all attribute types
correctly including byte arrays and multi-valued collections:
```powershell
Import-Module ActiveDirectory -ErrorAction Stop
$cfgNC       = (Get-ADRootDSE).configurationNamingContext
$containerDN = "CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC"
$src  = Get-ADObject -Identity "CN=$SourceTemplateName,$containerDN" -Properties *
# ... build $other hashtable skipping identity/auto-generated attributes ...
New-ADObject -Name $TemplateName -Type 'pKICertificateTemplate' `
             -Path $containerDN -OtherAttributes $other
```
The updated script is in `Lab-Kit\03-DomainController\New-CertificateTemplates.ps1`.
After pushing the fixed script to Lab-DC01, the template creation completes successfully.

---

### `Lab-Kit\03-DomainController\README.md` — Network Prerequisites Fix

**Problem:** `Build-CAC-Lab.ps1` fails at `Install-ADDSForest` with
`"TCP/IP networking protocol must be properly configured"` when the VM's network
adapter is Disconnected. Root cause: External virtual switch bound to a physical NIC
that has no link (host using WiFi, or Ethernet unplugged) leaves the VM adapter
with Media Disconnected state. `Install-ADDSForest` requires an Up adapter with
a static IP.

**Fix:** Use a Hyper-V Internal switch instead of External. Internal switch is always
Up regardless of physical NIC state:
```powershell
New-VMSwitch -Name "LabInternal" -SwitchType Internal
Connect-VMNetworkAdapter -VMName "Lab-DC01" -SwitchName "LabInternal"
Connect-VMNetworkAdapter -VMName "Lab-Workstation01" -SwitchName "LabInternal"
```

Then set static IP and run the build in one Invoke-Command block so the IP
can't drift between steps. See `03-DomainController\README.md` for full command.

---

### `Lab-Kit\02-OfflineRootCA\README.md` — New Sections Added

- Added BOM fix step (required before first transfer)
- Added loopback adapter setup (required for AD CS install)
- Added OVERRIDE explanation for air-gap check
- Added recovery steps for "already installed" failure
- Added post-ceremony transfer + cleanup sequence with expected file list

---

## 2026-05-27 — Session 2 (Glenn Byron)

### Before-MFA SCAP Baseline Scan Completed — Lab-DC01

**Score:** 44.95% [RED] — expected. IA-2 smart card controls not yet enforced.

**SCC version:** 5.10.2  
**STIG content:** MS_Windows_Server_2022_STIG (used with "Run content regardless of
applicability" — Windows Server 2025 does not have its own CPE in this content version)  
**Session folder:** `C:\Users\Administrator\SCC\Sessions\2026-05-27_084947\` (on Lab-DC01)  
**Staged at:** `C:\CAC-Lab-Kit-20260526\Lab-Kit\05-Compliance\Before-MFA\Before-MFA-DC01-Results.zip`

**SCC CPE applicability override:** SCC reported "content is not applicable to this
platform" for Windows Server 2025. Fix: open Content Details panel in SCC, check
"Run content regardless of applicability." Scan then proceeds normally.

---

### SMB File Transfer Between DC and Hyper-V Host — Auth Blocked

**Problem:** `Copy-Item` from Lab-DC01 to `\\10.10.10.1\LabShare\` failed with
"The user name or password is incorrect" even though the share had `Everyone / Full
Access`. Lab-DC01 connects as `LAB\Administrator` (domain account). The Hyper-V host
is a workgroup machine — it requires a **local host account** for NTLM auth. Domain
accounts are unknown to the host's SAM database.

**Fix:** Create a local account on the Hyper-V host with credentials that match what
the DC will authenticate with, then use `net use` on the DC to establish the session
with explicit credentials:

```powershell
# On Hyper-V host:
net user LabTransfer "<LAB-ADMIN-PASSWORD>" /add
net localgroup Administrators LabTransfer /add
Grant-SmbShareAccess -Name "LabShare" -AccountName "LabTransfer" -AccessRight Full -Force
icacls "C:\LabShare" /grant "LabTransfer:(OI)(CI)M" /T

# On Lab-DC01:
net use \\10.10.10.1\LabShare /user:LabTransfer "<LAB-ADMIN-PASSWORD>"
Copy-Item "C:\SCC\Before-MFA-DC01-Results.zip" -Destination "\\10.10.10.1\LabShare\" -Force
net use \\10.10.10.1\LabShare /delete
```

**Root cause:** Windows NTLM authentication for SMB requires a matching account in the
target machine's local SAM or Active Directory. Share-level permissions (`Everyone`) grant
access once authenticated but do not bypass authentication itself. The LabTransfer local
account provides the matching credential anchor.

**Note for future scans:** Before any DC → host file transfer, create the LabTransfer
account on the host if it doesn't already exist. Alternatively, push results via VHDX
passthrough (reliable but slower).

---

### Before-MFA SCAP Baseline Scan Completed — Lab-Workstation01

**Score:** 42.2% [RED] — expected. Smart card enforcement not yet active.

**SCC version:** 5.10.2  
**STIG content:** MS_Windows_Server_2022_STIG (CPE override — same as DC01)  
**Session folder:** `C:\Users\Administrator.LAB\SCC\Sessions\2026-05-27_092002\` (on Lab-Workstation01)  
**Staged at:** `C:\CAC-Lab-Kit-20260526\Lab-Kit\05-Compliance\Before-MFA\Before-MFA-WS01-Results.zip`

**Note:** Domain-joined workstation profile path is `Administrator.LAB` (not `Administrator`).
SCC writes results to `C:\Users\Administrator.LAB\SCC\Sessions\` — use this path for
all staging commands on Lab-Workstation01.

**Transfer method:** PowerShell Direct works on Lab-Workstation01. Results pulled directly
from VM to host via `Copy-Item -FromSession` — no VHDX passthrough or SMB workaround needed.

**Both Before-MFA baselines are now complete:**

| VM | Score | Zip |
|----|-------|-----|
| Lab-DC01 | 44.95% [RED] | `Before-MFA\Before-MFA-DC01-Results.zip` |
| Lab-Workstation01 | 42.2% [RED] | `Before-MFA\Before-MFA-WS01-Results.zip` |

---

### `Lab-Kit\05-Compliance\Stage-Reports.ps1` — Runs on Local Machine Only

**Note:** `Stage-Reports.ps1` expects `%USERPROFILE%\SCC\Results` on the machine
where it is run. Since the SCC scan ran on Lab-DC01 (not the Hyper-V host), the script
cannot auto-locate the scan folder from the host.

**Workaround for DC scans:** Manually zip the SCC session folder on Lab-DC01, transfer
the zip to the host, extract to
`C:\CAC-Lab-Kit-20260526\Lab-Kit\05-Compliance\Before-MFA\`, and commit directly.
The zip approach preserves all raw output (HTML, XML, ARF) for review and archiving.

For scans run on Lab-Workstation01 (which may support PowerShell Direct), `Stage-Reports.ps1`
can be run normally from `C:\CAC-Lab-Kit-20260526\Lab-Kit\05-Compliance\`.

---

### Phase 9 — Smart Card Enrollment: Four Bugs in New-TokenEnrollment.ps1 and PKI Setup

---

#### Bug 1 — `extensionAttribute1` Not in Base AD Schema

**Problem:** `New-TokenEnrollment.ps1` uses `extensionAttribute1` to carry the RA
authorization flag between phases. This attribute is part of the Exchange schema and does
not exist in a base Windows Server Active Directory installation without Exchange.
Script fails immediately after the identity checklist with:
```
AD lookup failed: One or more properties are invalid. Parameter name: extensionAttribute1
```

**Fix:** Changed `$RA_ATTR` from `"extensionAttribute1"` to `"pager"`. The `pager`
attribute is single-valued, always present in the base AD schema, and unused in this lab:
```powershell
# In New-TokenEnrollment.ps1 line ~85:
# Before:
$RA_ATTR = "extensionAttribute1"
# After:
$RA_ATTR = "pager"
```
Fix applied to both the host copy and the DC copy via in-place text replace.

---

#### Bug 2 — Built-in Administrator Account Has No UPN by Default

**Problem:** After fixing Bug 1, the script still fails with:
```
AD lookup failed: User 'administrator@lab.local' not found in Active Directory
```
The built-in Administrator account in a new AD domain has an empty `UserPrincipalName`
field. The script searches by UPN, so it cannot find the account.

**Fix:** Set the UPN on the Administrator account before running enrollment:
```powershell
Set-ADUser -Identity Administrator -UserPrincipalName "administrator@lab.local"
```

---

#### Bug 3 — CardIssuer Cannot Write to C:\Windows\Logs\

**Problem:** The Issuer phase writes an audit log to `C:\Windows\Logs\TokenEnrollment.log`.
The CardIssuer account (Domain Admins but not local Administrator) does not have write
access to `C:\Windows\Logs\` on Lab-DC01. Log write fails with:
```
[!!] Could not write to log file: C:\Windows\Logs\TokenEnrollment.log - Access is denied
```
The enrollment ceremony itself still completes — the log error is non-fatal.

**Workaround:** Run the Issuer phase from the LAB\Administrator account (which has
local admin rights), or pre-create the log file and grant CardIssuer write access:
```powershell
New-Item -Path "C:\Windows\Logs\TokenEnrollment.log" -ItemType File -Force
icacls "C:\Windows\Logs\TokenEnrollment.log" /grant "LAB\CardIssuer:(M)"
```

---

#### Bug 4 — SmartCardLogon Template Not Published to CA

**Problem:** `New-CertificateTemplates.ps1` creates the SmartcardLogon and
SmartCard-AdminLogon templates in AD but does not publish them to the issuing CA.
The templates exist in `CN=Certificate Templates,...` in AD but are not listed in the
CA's published template list. The Certificate Enrollment wizard shows all templates as
"Unavailable" because the CA has no smart card templates to offer.

**Diagnosis:**
```powershell
# From workstation — CA reachable but no smart card templates:
certutil -config "Lab-DC01\LAB-CA" -catemplates | Select-String "Smart"
# Returns nothing until published
```

**Fix:** Publish both templates to the CA manually:
```powershell
Add-CATemplate -Name "SmartcardLogon" -Force
Add-CATemplate -Name "SmartCard-AdminLogon" -Force
```
Note: The `AdminSmartCardLogon` name used in the script README is wrong — the actual AD
object name created by `New-CertificateTemplates.ps1` is `SmartCard-AdminLogon` (hyphenated).

---

#### Bug 5 — SmartCardLogon Template Has No Enroll Permission for Users

**Problem:** After publishing the templates, the Certificate Enrollment wizard still shows
all smart card templates as "Unavailable." The template ACL only had Enterprise Admins
with Full Control — no Enroll right for Domain Users or Authenticated Users.

**Diagnosis:**
```powershell
certutil -config "Lab-DC01\LAB-CA" -catemplates
# Shows: SmartcardLogon: Smartcard Logon -- Auto-Enroll: Access is denied.
```

**Fix:** Using PSPKI (already installed on Lab-DC01), grant Authenticated Users
Read + Enroll on both smart card templates:
```powershell
Import-Module PSPKI
foreach ($name in @("SmartcardLogon", "SmartCard-AdminLogon")) {
    $t = Get-CertificateTemplate -Name $name
    $acl = $t | Get-CertificateTemplateAcl
    $acl | Add-CertificateTemplateAcl -Identity "Authenticated Users" `
           -AccessType Allow -AccessMask Read, Enroll | Set-CertificateTemplateAcl
}
```

---

#### Pre-Enrollment Setup Steps Required (Run Once on Lab-DC01)

These steps must be completed before the enrollment ceremony works:

```powershell
# 1. Set UPN on Administrator account
Set-ADUser -Identity Administrator -UserPrincipalName "administrator@lab.local"
Set-ADUser -Identity CardIssuer    -UserPrincipalName "CardIssuer@lab.local"

# 2. Create CardIssuer account (if not already done)
$pw = ConvertTo-SecureString "<LAB-ADMIN-PASSWORD>" -AsPlainText -Force
New-ADUser -Name "CardIssuer" -SamAccountName "CardIssuer" `
           -UserPrincipalName "CardIssuer@lab.local" `
           -AccountPassword $pw -Enabled $true -PasswordNeverExpires $true
Add-ADGroupMember -Identity "Domain Admins" -Members "CardIssuer"

# 3. Publish smart card templates to CA
Add-CATemplate -Name "SmartcardLogon"      -Force
Add-CATemplate -Name "SmartCard-AdminLogon" -Force

# 4. Grant Authenticated Users Enroll on templates
Import-Module PSPKI
foreach ($name in @("SmartcardLogon", "SmartCard-AdminLogon")) {
    $t   = Get-CertificateTemplate -Name $name
    $acl = $t | Get-CertificateTemplateAcl
    $acl | Add-CertificateTemplateAcl -Identity "Authenticated Users" `
           -AccessType Allow -AccessMask Read, Enroll | Set-CertificateTemplateAcl
}

# 5. Fix CardIssuer log write access
New-Item -Path "C:\Windows\Logs\TokenEnrollment.log" -ItemType File -Force | Out-Null
icacls "C:\Windows\Logs\TokenEnrollment.log" /grant "LAB\CardIssuer:(M)"
```

---

#### Card Reader Passthrough to VM (Enhanced Session Required)

Certificate enrollment writes the cert directly to the GIDS card. The card reader must
be accessible to the domain-joined VM performing the enrollment. Hyper-V Enhanced Session
(RDP-based) redirects the host's smart card reader to the VM automatically.

**Requirement:** Connect to Lab-Workstation01 via Enhanced Session (View → Enhanced
Session in the VM connection window). The GIDS card is then visible inside the VM:
```
certutil -scinfo   ← shows "Identive SCR33xx ... SCARD_STATE_PRESENT"
```

**Note:** "SCARD_STATE_INUSE / The card is being shared by a process" is normal when
both the host and the VM can see the card simultaneously. Does not block enrollment.

---

### PowerShell Direct to Lab-DC01 — Persistent Auth Failure (Unresolved)

**Problem:** `New-PSSession -VMName "Lab-DC01" -Credential $cred` consistently returns
"credential is invalid" throughout this lab build. The account is NOT locked
(BadLogonCount=0 confirmed). Clocks are synchronized (both UTC, both matching).
Integration Services are running and all checkboxes enabled in VM settings.

**Investigated:**
- Account lockout: `Search-ADAccount -LockedOut` — no locked accounts
- Time skew: DC and host both showing 11:15 UTC at time of check — no skew
- Integration Services: Heartbeat, Key-Value Pair, Time Sync, VSS all checked
- Basic vs Enhanced Session: Confirmed Basic Session (required for PowerShell Direct)

**Root cause:** Not definitively identified. Possibly related to how Lab-DC01 was
promoted — Hyper-V VM Integration may not have completed credential handshake correctly.

**Workaround:** Use the Lab-DC01 console directly for all DC-side operations. File transfers
use VHDX passthrough (for large files like SCC installer) or SMB with LabTransfer account
(for results staging).

---

### Phase 9 — SmartCardLogon Template CSP Fix

**Problem:** The SmartcardLogon template's `pKIDefaultCSPs` attribute was not set to
smart card providers. `certreq -enroll` enrolled the certificate using a **software** key
stored in the user profile instead of writing it to the card.

**Diagnosis:** `certutil -scinfo` showed "Missing stored keyset" on both providers
even after enrollment completed successfully.

**Fix:** Set both smart card CSPs on the template AD object:
```powershell
$cfgNC = (Get-ADRootDSE).configurationNamingContext
$templateDN = "CN=SmartcardLogon,CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC"
Set-ADObject -Identity $templateDN -Replace @{
    pKIDefaultCSPs = @(
        "1,Microsoft Base Smart Card Crypto Provider",
        "2,Microsoft Smart Card Key Storage Provider"
    )
}
```

---

### Phase 9 — certmgr.msc Shows All Templates Unavailable (Workaround)

**Problem:** Even after publishing templates and granting Enroll permissions, the
Certificate Enrollment wizard in certmgr.msc continued to show SmartcardLogon as
"Unavailable." The wizard performs extra CSP validation at the UI layer.

**Workaround:** Bypass certmgr.msc entirely and use `certreq` with an explicit INF file.
Save the following to `C:\Temp\sclogon.inf` on Lab-Workstation01:

```ini
[Version]
Signature="$Windows NT$"

[NewRequest]
Subject = "CN=Administrator"
KeyLength = 2048
KeySpec = 1
MachineKeySet = FALSE
Exportable = FALSE
UserProtected = TRUE
ProviderName = "Microsoft Base Smart Card Crypto Provider"
ProviderType = 1
RequestType = PKCS10

[RequestAttributes]
CertificateTemplate = SmartcardLogon
```

Key notes:
- `ProviderType = 1` is required for CAPI (Microsoft Base Smart Card Crypto Provider).
  CNG providers (`Microsoft Smart Card Key Storage Provider`) need no ProviderType line.
- `UserProtected = TRUE` triggers PIN prompt during key generation.
- Do NOT include `[Extensions]` with SAN — the CA builds subject/SAN from AD based on
  template flags (`msPKI-Certificate-Name-Flag = 0x82000000`).

---

### Phase 9 — certreq -new Suppresses Enrollment When Cert Already Exists

**Problem:** `certreq -new` with `CertificateTemplate = SmartcardLogon` uses the AD
enrollment policy (ldap:). When a valid cert for that template already exists in the
user's Personal store, the policy silently returns without creating a .req file or
prompting for PIN.

**Fix:** Delete the existing cert first, or use `-f` flag:
```powershell
# Delete existing software-key cert first
Remove-Item "Cert:\CurrentUser\My\<thumbprint>" -Force
# Then force a fresh request
certreq -f -new C:\Temp\sclogon.inf C:\Temp\sclogon.req
```

---

### Phase 9 — GIDS Card Blocked During Enrollment

**Problem:** The CardLogix GIDS card became PIN-blocked (retry counter = 0) during
`certreq -new`. Root cause: the Windows GIDS minidriver retried PIN verification
internally during key generation attempts, exhausting the 3-attempt counter.

**Recovery attempted:**
- `gids-tool --unblock --admin-key <default>` → `Security status not satisfied` — Windows
  GIDS minidriver generated a **random** admin key during card initialization. Default
  key `010203040506070801020304050607080102030405060708` does not match.
- `pkcs15-init --erase-card` → `Couldn't bind to the card: Requested object not found` —
  OpenSC cannot access the GIDS filesystem structure on a blocked card.
- **Card is unrecoverable** without the original admin key or CardLogix factory tools.

**Lesson:** CardLogix GIDS cards managed by the Windows GIDS minidriver use a randomly
generated admin key that is not stored anywhere accessible on the host. For lab use,
prefer a **YubiKey 5 NFC** (ykman allows complete PIV reset in 2 seconds) or
**HID Crescendo C2300** (same FIPS 201 chip platform as government PIV/CAC cards).

---

### Phase 9 — Pivot to Windows Virtual Smart Card (vTPM)

**Background:** With the physical GIDS card unrecoverable, the lab pivoted to a
TPM-backed Windows Virtual Smart Card. For SCAP scanning, enrollment ceremony
documentation, and smart card logon testing, a VSC is functionally equivalent to
a physical card.

**Requirements:**
1. Lab-Workstation01 must be a Generation 2 Hyper-V VM (supports vTPM)
2. vTPM must be enabled (NOT enabled by default — must be done from host)
3. `tpmvscmgr.exe` must run from a **console session** — it fails inside Enhanced
   Session (RDP/Terminal Services) with `0x800704d3 The request was aborted`

**vTPM enable procedure (run on Hyper-V host, VM must be off):**
```powershell
Stop-VM "Lab-Workstation01" -Force
Set-VMKeyProtector -VMName "Lab-Workstation01" -NewLocalKeyProtector
Enable-VMTPM -VMName "Lab-Workstation01"
Start-VM "Lab-Workstation01"
# Verify:
(Get-VMSecurity -VMName "Lab-Workstation01").TpmEnabled   # → True
```

**VSC create procedure (Basic Session on Lab-Workstation01):**
```
View → Basic Session   ← must switch from Enhanced Session first
```
```powershell
tpmvscmgr.exe create /name "LabVSC" `
    /pin PROMPT `
    /pinpolicy minlen 6 `
    /adminkey DEFAULT `
    /generate
# PIN: 123456
```
Output on success:
```
TPM Smart Card created.
Smart Card Reader Device Instance ID = ROOT\SMARTCARDREADER\0000
```
The VSC persists across reboots. Only the **creation** step requires Basic Session —
cert enrollment and smart card logon work from Enhanced Session.

**Cert enrollment onto VSC:**
```powershell
# From Basic Session or Enhanced Session on Lab-Workstation01

# Remove any existing software-key cert if present
# Remove-Item "Cert:\CurrentUser\My\<old-thumbprint>" -Force

# Generate key in vTPM and write CSR
certreq -f -new C:\Temp\sclogon.inf C:\Temp\sclogon.req
# Output: CertReq: Request Created   (no PIN prompt — key goes straight to vTPM)

# Submit to CA
certreq -submit -config "Lab-DC01\LAB-CA" C:\Temp\sclogon.req C:\Temp\sclogon.cer

# Install cert (links it to vTPM key)
certreq -accept C:\Temp\sclogon.cer

# Verify — no NTE_BAD_KEYSET error = key is in vTPM
certutil -scinfo
# Expected final lines:
#   Displayed cert for reader: Microsoft Virtual Smart Card 0
#   CertUtil: -SCInfo command completed successfully.
```

---

### Phase 9 — Issuer Phase: CardIssuer Lacks Set-ADUser Rights

**Problem:** The Issuer phase script sets `SmartcardLogonRequired = $true` on the AD
account. CardIssuer does not have sufficient rights to write this attribute:
```
Set-ADUser : Insufficient access rights to perform the operation
```

**Impact:** Non-fatal — ceremony completes, audit entry is written, only this one flag
is not set.

**⚠️ CRITICAL — DO NOT manually set this flag on LAB\Administrator:**
```powershell
# DO NOT RUN THIS ON THE ADMINISTRATOR ACCOUNT
Set-ADUser -Identity Administrator -SmartcardLogonRequired $true
# ^ This locks out ALL password-based login for Administrator permanently
```

Setting `SmartcardLogonRequired = $true` on the Administrator account is a **per-user
AD flag** that blocks ALL password-based login for that account — console, PowerShell
Direct, RDP — regardless of any GPO or registry settings. It cannot be reversed
without another Domain Admin account or DSRM access.

**Note for this lab:** Leave the Administrator flag unset. The workstation GPO
(`scforceoption=1`) enforces smart card at the machine level on Lab-Workstation01
only. The AD account flag would enforce it for the Administrator account on every
machine including Lab-DC01, permanently removing break-glass access.

---

### Session 3 — DC01 Lockout Root Cause: SmartcardLogonRequired on Administrator Account

**Date:** 2026-05-28

**Problem:** After Phase 9, LAB\Administrator could not log into Lab-DC01. The login
screen showed "You must use Windows Hello or a smart card to sign in." Multiple rounds
of registry editing and GPO SYSVOL cleanup failed to resolve it.

**Root cause:** The `SmartcardLogonRequired` flag was set on the `LAB\Administrator`
AD account (`userAccountControl` includes `UF_SMARTCARD_REQUIRED = 0x40000`). This
per-user flag is **completely separate from** the machine-wide `scforceoption=1`
registry value. Removing `scforceoption` from the registry and disabling/deleting the
domain GPO had no effect because the enforcement was on the account itself.

**Confirmed:** `LAB\CardIssuer` (same Domain Admins group, no `SmartcardLogonRequired`
flag) could log into DC01 normally while Administrator was blocked. This is the
diagnostic: if one domain admin can log in but another cannot, the issue is per-user,
not machine-wide.

**Fix (run as LAB\CardIssuer):**
```powershell
Set-ADUser -Identity Administrator -SmartcardLogonRequired $false
```

**What the machine-wide lockout troubleshooting DID fix (also needed):**
- Smart card enforcement GPO was linked at domain root → DC01 was hit by `scforceoption=1`
- GPO has been relinked to `OU=Workstations,DC=lab,DC=local` only
- `Lab-Workstation01` computer account moved to Workstations OU

**CardIssuer designated as Break-Glass account:**
`LAB\CardIssuer` is now the primary break-glass account for Lab-DC01. It is a Domain
Admin that will never have `SmartcardLogonRequired` set. See WALKTHROUGH.md
Break-Glass Accounts section for details.

**Lesson learned:** There are TWO independent smart card enforcement mechanisms:
1. **Machine-wide (GPO/registry):** `scforceoption=1` — applies to all users on the
   machine. Fix: remove the registry value or unlink/scope the GPO.
2. **Per-user (AD account flag):** `SmartcardLogonRequired` — applies to that user on
   every machine. Fix: `Set-ADUser -SmartcardLogonRequired $false`. Survives all GPO
   and registry changes.

Both can be active simultaneously. Always check both when troubleshooting lockouts.

---

### Phase 9 — Enrollment Ceremony and Smart Card Logon: COMPLETE

**Date:** 2026-05-27

**Token:** Windows TPM Virtual Smart Card — `Microsoft Virtual Smart Card 0`
**Device instance:** `ROOT\SMARTCARDREADER\0000`
**PIN:** `123456` (set during tpmvscmgr create, minlen 6 policy)
**Admin key:** DEFAULT (`010203040506070801020304050607080102030405060708`)

**Ceremony results:**
| Step | Account | Result |
|------|---------|--------|
| RA phase | LAB\Administrator | ✅ Authorized at `20260527-095317` |
| AC-5 check | (script) | ✅ Blocked Administrator from Issuer phase |
| Issuer phase | LAB\CardIssuer | ✅ Ceremony complete |
| Token serial recorded | | `ROOT\SMARTCARDREADER\0000` |

**certutil -scinfo:** Completed successfully — cert on Microsoft Virtual Smart Card 0
**EKUs:** Client Authentication + Smart Card Logon ✓
**Issuer:** CN=LAB-CA, DC=lab, DC=local ✓
**Valid:** 5/27/2026 → 5/27/2027 ✓

**Smart card logon test: ✅ PASS**
Lock screen (Win+L) → Sign-in options → Smart card tile → PIN `123456` → LAB\Administrator logged in successfully.

---

## 2026-06-01 — Session 4 (Glenn Byron)

### WS01 Domain Rejoin — Computer Name Truncated to 15 Characters

**Problem:** `Get-ADComputer -Filter "Name -eq 'Lab-Workstation01'"` returned no results.
The computer account had been deleted from AD during the DC01 lockout recovery work.

**Root cause of rejoin failure:** WS01's DNS was pointing to a public server, not DC01.
`Add-Computer` resolved the domain name via DNS and failed with "The specified domain
either does not exist or could not be contacted" even though ping to DC01's IP succeeded.

**Fix:**
```powershell
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses "10.10.10.10"
```

**Computer name truncation:** `Lab-Workstation01` (17 chars) exceeds the NetBIOS 15-character
limit. Windows silently truncated it to `LAB-WORKSTATION` in AD. Always use names ≤ 15 chars.

**Rejoin command used:**
```powershell
Add-Computer -DomainName "lab.local" `
    -Credential (Get-Credential "LAB\Administrator") `
    -OUPath "OU=Workstations,DC=lab,DC=local" `
    -Restart -Force
```

Computer landed in: `CN=LAB-WORKSTATION,OU=Workstations,DC=lab,DC=local` ✅

---

### SmartCard Policy GPO — scforceoption=1 Added

With WS01 confirmed in the Workstations OU, `scforceoption=1` was safely added to the
SmartCard Policy GPO. All three enforcement values are now set:

```powershell
Set-GPRegistryValue -Name "SmartCard Policy" `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "scforceoption" -Type DWord -Value 1
```

| ValueName | Value | NIST Control |
|---|---|---|
| scforceoption | 1 | IA-2(11) — smart card required for interactive logon |
| ScRemoveOption | 1 | AC-11 — lock workstation on card removal |
| InactivityTimeoutSecs | 900 | AC-11 — 15-minute idle lock |

**GPO scope:** `OU=Workstations,DC=lab,DC=local` only. DC01 is NOT in this OU and is
NOT affected. `gpupdate /force` confirmed on both DC01 and LAB-WORKSTATION.

---

### After-MFA SCAP Scans Completed

Both VMs scanned with SCC 5.10.2 after smart card enforcement was active.

**SCC results path (confirmed):** `C:\Users\Administrator\SCC\Sessions\<timestamp>\`
(NOT `C:\Users\Administrator\SCC\Results\` — that path does not exist)

| VM | Session | Score | Delta vs Before-MFA |
|---|---|---|---|
| Lab-DC01 | 2026-05-28_113752 | **42.66% [RED]** | -2.29pp (DC intentionally excludes scforceoption) |
| LAB-WORKSTATION | 2026-05-28_114956 | **42.2% [RED]** | 0pp (same benchmark, same baseline) |

**Before-MFA reference scores:**
| VM | Score |
|---|---|
| Lab-DC01 | 44.95% [RED] |
| LAB-WORKSTATION | 42.2% [RED] |

**Note on score:** The STIG benchmark covers hundreds of controls. Smart card enforcement
addresses IA-2(11) and AC-11. The overall score delta is small. The meaningful result is
that smart card logon is WORKING — Event 4768 with Pre-Auth Type 16 confirms PKINIT.

---

### CRL Revocation Error on WS01 Login

**Symptom:** WS01 login screen shows "The revocation status of the authentication
certificate could not be determined."

**Cause:** `scforceoption=1` is active and Windows is trying to validate the certificate
revocation list. The HTTP CRL Distribution Point is not reachable (IIS not installed on
DC01). The LDAP CDP should work for domain-joined machines.

**Fix:** Republish CRL on DC01:
```powershell
certutil -crl
```

See TROUBLESHOOTING.md for full entry.

---

### Compliance Reports Staged to Host

Results pulled from DC01 and WS01 VMs to host machine via admin share:

```
Compliance-Reports\
  Before-MFA\
    Before-MFA-DC01-Results.zip   (0.6 MB — session 2026-05-27_084947)
    Before-MFA-WS01-Results.zip   (0.6 MB — session 2026-05-27_092002)
  After-MFA\
    DC01\2026-05-28_113752\       (full SCC session — Results, Logs, HTML viewer)
    WS01\2026-05-28_114956\       (full SCC session — Results, Logs, HTML viewer)
```

Export ZIP: `CAC-Lab-Export-20260601.zip` (97.8 MB) — includes all docs + compliance reports.

---

### TROUBLESHOOTING.md Created

New file: `C:\CAC-Lab-Kit-20260526\TROUBLESHOOTING.md`

Running FAQ covering every real problem encountered in the lab:
- Smart card lockout (two-mechanism root cause)
- GPO domain-root scope lockout
- SYSVOL folder missing (GPT.ini fix)
- DSRM limitations in single-DC lab
- WS01 domain rejoin (DNS fix, 15-char name limit)
- SCC results path, After-MFA file vs folder
- General PowerShell/registry gotchas

---

### Checkpoint: 05-After-Scan

All three VMs checkpointed on 2026-06-01 14:09:

```
20260601-1409-05-After-Scan
  Lab-OfflineRootCA  ✅
  Lab-DC01           ✅  (Production/VSS — VM was running)
  Lab-Workstation01  ✅
```

To restore: `.\New-LabSnapshot.ps1 -Mode Restore -Label "05-After-Scan"`

---

### Next Phase: 06-PhysicalEndpoint

Physical laptop domain join, Virtual Smart Card enrollment, Windows 11 STIG SCAP scan,
and VPN EAP-TLS test. See `Lab-Kit\06-PhysicalEndpoint\Add-Physical-Laptop.md`.

---

## 2026-06-02 — Session 4 Continued (Glenn Byron)

### WO02 Physical Laptop — Domain Join and Smart Card Enrollment Complete

**Machine:** Physical laptop, Windows 11 Pro, TPM 2.0
**Computer account:** `CN=WO02,OU=Workstations,DC=lab,DC=local`
**Enrolled user:** `LAB\labtech` / `labtech@lab.local`
**Card type:** TPM Virtual Smart Card (`ROOT\SMARTCARDREADER\0000`)
**PIN:** 123456
**Cert thumbprint:** <LABTECH-CERT-THUMBPRINT>
**Cert valid:** 6/2/2026 → 6/2/2027

**Smart card logon: ✅ PASS** — tested via RDP (`mstsc /v:10.10.20.30`), PIN prompt appeared, LAB\labtech logged in successfully.

---

### Network Topology Change — External Switch + 10.10.20.x Subnet

Added second NIC to DC01 on External switch to enable physical laptop connectivity
without disrupting LabInternal (10.10.10.x) VMs.

| Adapter | IP | Purpose |
|---|---|---|
| `vEthernet (LabInternal)` | 10.10.10.1 | Host ↔ VM management (unchanged) |
| `vEthernet (External)` | 10.10.20.1 | Host ↔ physical laptop segment |
| DC01 NIC1 (LabInternal) | 10.10.10.10 | Domain/DNS/CA (unchanged) |
| DC01 NIC2 (External) | 10.10.20.10 | Physical laptop access |
| WO02 (physical) | 10.10.20.30 | Physical endpoint |

**Root cause of IP conflict:** `vEthernet (LabInternal)` already owned 10.10.10.0/24 route. Attempted to set 10.10.10.1 on External — Windows refused. Fix: use 10.10.20.x subnet for External segment.

**netsh fix for IP assignment (name-based command failed):**
```powershell
netsh interface ipv4 set address name=23 static 10.10.20.1 255.255.255.0
```

---

### DC01 — Kerberos Authentication Certificate Enrolled

**Problem:** Smart card logon failed with "Signing in with a security device isn't supported for your account." DC01 had no Kerberos Authentication certificate — required for PKINIT smart card authentication.

**Fix:**
```powershell
certreq -enroll -machine KerberosAuthentication
```

**Root cause:** Default Enterprise Root CA deployment does not auto-enroll DC for KerberosAuthentication template because Domain Controllers group lacked Enroll rights. Fixed by granting Domain Controllers Read+Enroll+AutoEnroll via PSPKI, then requesting directly with certreq.

---

### SmartcardLogon Template — Enroll Permission Fix

**Problem:** labtech cert request denied with `CERTSRV_E_TEMPLATE_DENIED`. PSPKI `Add-CertificateTemplateAcl` with `-AccessMask Read,Enroll` only added Read — Enroll was silently dropped.

**Fix:** Used AD extended rights directly (Certificate Enrollment GUID `0e10c968-78fb-11d2-90d4-00c04f79dc55`) to set Enroll for Authenticated Users on the SmartcardLogon template AD object.

---

### labtech User Created

```powershell
New-ADUser -Name "labtech" -SamAccountName "labtech" `
    -UserPrincipalName "labtech@lab.local" `
    -AccountPassword (ConvertTo-SecureString "<LAB-LABTECH-PASSWORD>" -AsPlainText -Force) `
    -Enabled $true -PasswordNeverExpires $true `
    -Path "OU=Workstations,DC=lab,DC=local"
```

labtech is a standard domain user. Temporary local admin during enrollment only (removed after cert enrolled).

---

### ONBOARDING.md Created

New file: `C:\CAC-Lab-Kit-20260526\ONBOARDING.md`

Complete start-to-finish enrollment guide including:
- Lab environment map and account table
- Add a new computer to domain (5 steps)
- Create a new domain user (all variants)
- Smart card enrollment — complete guide with both VSC and physical card paths
- Zero trust notes (temp local admin, removal after enrollment)
- Checkpoint commands

---

### Event 4768 — PKINIT Smart Card Authentication Confirmed

**Date:** 2026-06-02 08:25

Captured on DC01 Security log — confirms smart card Kerberos pre-authentication (PKINIT)
at the protocol level. This is the primary NIST IA-2(11) portfolio evidence.

```
Event ID:              4768 (Kerberos TGT Request)
Account:               labtech
Pre-Authentication:    Type 16 (PKINIT — certificate used)
Client Address:        ::ffff:10.10.20.30  (WO02 physical laptop)
Certificate Issuer:    LAB-CA
Certificate Serial:    140000000B8DE8DC400FC57E7F00000000000B
Certificate Thumbprint: <LABTECH-CERT-THUMBPRINT>
Result Code:           0x0 (Success)
```

Contrast: Administrator's simultaneous 4768 shows Pre-Auth Type **2** (password, no cert).
This confirms the zero trust model — labtech enforced to smart card, Administrator retains
password break-glass access.

**NIST controls satisfied:**
- IA-2(11) - Remote access MFA via certificate-based Kerberos (PKINIT)
- AC-11 - Session lock on card removal (ScRemoveOption=1)
- AC-5 - Separation of duties enforced in enrollment ceremony

---

### WO02 SCAP Scan - Windows 11 STIG (After-SmartCard)

**Date:** 2026-06-02
**Score: 37% [RED]**
**SCC version:** 5.10.2
**Benchmark:** Windows 11 STIG (DISA STIG SCAP Content - bundled with SCC 5.10.2)
**Session:** `2026-06-02_104513`
**Scanned as:** LAB\labtech (smart card enforcement active during scan)
**Staged at:** `Compliance-Reports\Laptop\After-SmartCard\2026-06-02_104513\`

This is the baseline scan for WO02 after domain join and smart card enrollment.
No hardening has been applied yet - 37% represents the out-of-box Windows 11 Pro
state with only smart card GPO active.

---

### Checkpoint: 06-WO02-SmartCard-Working

```
20260602-0812-06-WO02-SmartCard-Working
  Lab-OfflineRootCA  [OK]
  Lab-DC01           [OK]  (Production/VSS)
  Lab-Workstation01  [OK]  (Production/VSS)
```

To restore: `.\New-LabSnapshot.ps1 -Mode Restore -Label "06-WO02-SmartCard-Working"`

---

### Lessons Learned - Physical Endpoint Phase

| # | Lesson | Impact |
|---|---|---|
| 1 | VSC + cert enrollment MUST happen BEFORE scforceoption=1 | Critical - wrong order locks you out |
| 2 | certreq MUST run as the TARGET USER, not admin | Critical - cert goes to wrong store |
| 3 | DC needs KerberosAuthentication cert for PKINIT | Blocks all smart card logon without it |
| 4 | Use RDP, not VNC, for smart card testing | VNC blocks smart card PIN entry |
| 5 | Add-CertificateTemplateAcl drops Enroll right | Use AD extended rights GUID directly |
| 6 | tpmvscmgr DEFAULT admin key, not random | Random key = unrecoverable if PIN blocked |
| 7 | Smart card services need reboot to initialize cleanly | Restart alone may not be enough |
| 8 | Standard users need temp local admin for VSC setup | Remove immediately after enrollment |

---

## 2026-06-04 — Session 5 (Glenn Byron)

### PKI Health Monitor Baseline — Lab-DC01

Ran `Monitor-PKIHealth.ps1` 7 times across the day on Lab-DC01 as Administrator. All runs reported `Critical: False | Warning: False`. Final run at 12:18:49 captured a console screenshot for portfolio slot 6 (Demo-Walkthrough Step 6). The 12:07:50 run added the explicit `HEALTH-CHECK-PASS | No issues found` line after the script update below. Baseline cadence established for SAR § 3 / POAM pulse tracking. Artifacts staged at `Compliance-Reports/PKI-Health/2026-06-04/`. NIST controls demonstrated: CA-7 (Continuous Monitoring), SC-17 (PKI Certificates).

### `Lab-Kit\03-DomainController\Monitor-PKIHealth.ps1` — `.Count` Crash on Empty Pipeline Under StrictMode

**Symptom:** Script crashed in `Write-HealthSummary`:

```
The property 'Count' cannot be found on this object. Verify that the property exists.
At Monitor-PKIHealth.ps1:464 char:9
+     if ($critical.Count -eq 0 -and $warnings.Count -eq 0) {
```

**Root cause:** In PowerShell 5.1, when a pipeline produces zero output (e.g. `Where-Object` filtering an empty array), the result is `[AutomationNull]` — an internal type that is not a real array. Under `Set-StrictMode -Version Latest`, accessing `.Count` on `AutomationNull` throws `PropertyNotFoundException` even when the expression is wrapped in `@()`. This is a known PS 5.1 trap that surfaces only when there are no findings (i.e. happy path).

**Fix:**
- Replaced the `Where-Object` + `.Count` pattern in `Write-HealthSummary` with a `foreach` loop using plain integer counters (`$critCount`, `$warnCount`) and `[System.Collections.ArrayList]` collectors. Integer variables always support `-eq 0` without StrictMode issues.
- Added `if ($script:findings)` null guards in both `Write-HealthSummary` and `Send-AlertEmail` to prevent the same class of error if `$script:findings` is ever `$null` rather than `@()`.

**Why it didn't surface earlier:** Previous test runs on smaller environments had findings populated; only the all-clear path hits the empty-pipeline case.

### `Lab-Kit\07-ZeroTrust\Set-AuthenticationPolicySilo.ps1` — `Grant-ADAuthenticationPolicySiloAccess` Rejects Group Objects

**Symptom:** Running Phase 8.1.4 against the freshly-tiered AD:

```
Grant-ADAuthenticationPolicySiloAccess : Cannot find an object with identity:
  'Tier-0-Admins' under: 'DC=lab,DC=local'.
```

The error message is misleading — the group exists and is resolvable, but the cmdlet rejected it.

**Root cause:** `Grant-ADAuthenticationPolicySiloAccess -Account` only accepts individual user/computer accounts. Passing a security group (`Tier-N-Admins`) throws a terminating `ADIdentityNotFoundException` that bypasses `-ErrorAction SilentlyContinue`. Microsoft documents this in the cmdlet help but the error message points at the wrong thing.

A secondary issue caused the same crash during `-WhatIf` runs: steps 3-4 (grant + bind) executed even when the silo hadn't been created yet in dry-run mode (the silo object wasn't there to grant against).

**Fix:**
- Moved `Grant-ADAuthenticationPolicySiloAccess` into a per-member loop — each user/computer account in the admin group is granted individually.
- Added `$siloExists` guard so steps 3-4 are skipped when the silo is absent (including `-WhatIf` mode).
- Wrapped each AD call in `try/catch` to allow the loop to continue on per-account failures.
- Added inline note: re-run this script after populating admin groups to bind newly added accounts.

### Lessons Learned — Session 5

| # | Lesson | Impact |
|---|---|---|
| 9 | `Where-Object` + `.Count` is unsafe under StrictMode on the happy path | Empty pipeline returns `AutomationNull`, not `@()`. Use `foreach` + integer counters. |
| 10 | `Grant-ADAuthenticationPolicySiloAccess` only accepts user/computer accounts, not groups | Loop over `Get-ADGroupMember` and grant each member individually. Cmdlet error message blames the group identity, not the type mismatch. |
| 11 | Annotated AD ops in `-WhatIf` blocks still need existence guards | Steps that depend on an earlier dry-run-skipped step will crash. Add an `$xExists` check before each dependent step. |
| 12 | The "happy path" is where StrictMode bugs hide | Bugs only surface when the success branch executes. Test both populated and empty result sets. |

