# CAC Lab Troubleshooting FAQ

Ongoing log of problems encountered in the lab and how to fix them.
Add new entries at the top of each section as issues arise.

---

## Table of Contents

1. [Smart Card / Authentication](#smart-card--authentication)
2. [Group Policy](#group-policy)
3. [Active Directory & Domain](#active-directory--domain)
4. [SYSVOL & GPO Infrastructure](#sysvol--gpo-infrastructure)
5. [Workstation Domain Join](#workstation-domain-join)
6. [SCAP / Compliance Checker](#scap--compliance-checker)
7. [General Windows / PowerShell](#general-windows--powershell)

---

## Smart Card / Authentication

### "You must use Windows Hello or a smart card to sign in" — locked out of DC01

**Symptom:** DC01 login screen shows "You must use Windows Hello or a smart card" for ALL users including Administrator. Password-based login is blocked.

**Root Cause (two independent mechanisms — check BOTH):**

| # | Mechanism | Scope | How to check |
|---|-----------|-------|--------------|
| 1 | `scforceoption = 1` in registry / GPO | All users on the machine | `Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System` |
| 2 | `SmartcardLogonRequired` flag on AD user account | That user on every machine | `Get-ADUser Administrator -Properties SmartcardLogonRequired` |

**Fix for mechanism #1 (GPO):**
The GPO re-applies at every boot before the login screen appears. Editing the registry directly does not survive a reboot. You must fix the GPO itself:
```powershell
# Remove scforceoption from the GPO (run as Domain Admin)
Set-GPRegistryValue -Name "SmartCard Policy" `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "scforceoption" -Type DWord -Value 0
```
Or unlink the GPO from the OU that DC01 is in, then fix it.

**Fix for mechanism #2 (per-user AD flag) — THE ACTUAL CAUSE in this lab:**
Log in as `LAB\CardIssuer` (break-glass account — see below), then:
```powershell
# Reset Administrator password and clear the smart card requirement
$pw = ConvertTo-SecureString "YourNewP@ssw0rd!" -AsPlainText -Force
Set-ADAccountPassword -Identity Administrator -NewPassword $pw -Reset
Set-ADUser -Identity Administrator -SmartcardLogonRequired $false
```

**Critical warning:** Do NOT run `Set-ADUser -Identity Administrator -SmartcardLogonRequired $true` during normal lab work. This flag persists through reboots, GPO changes, and DSRM recovery. It is independent of all machine-wide settings.

---

### Break-glass accounts — when Administrator is locked out

| Account | Password | Permissions | Notes |
|---|---|---|---|
| `LAB\CardIssuer` | `YourNewP@ssw0rd!` | Domain Admins | Primary break-glass. No SmartcardLogonRequired set. Use to fix Administrator. |
| DSRM local admin | Set during DC promo | Local only | Last resort. AD DS does not start in DSRM in this lab config. |

**Rule:** CardIssuer and Administrator should NEVER both have `SmartcardLogonRequired = $true` at the same time.

---

### GPO re-applies scforceoption after registry edit on reboot

**Symptom:** You delete or set `scforceoption = 0` in the registry, reboot, and the lock screen returns. Registry shows it's back to 1.

**Cause:** Machine-side GPO is processed during boot, before the login screen. The GPO overwrites any manual registry edits.

**Fix:** Edit the GPO directly (see above) or delete/unlink the GPO. Registry edits alone will not survive a reboot while the GPO is active.

---

## Group Policy

### GPO accidentally linked to domain root — locks out all machines including DC

**Symptom:** After running a smart card enforcement script, ALL machines (including DC01) require smart cards. Even new, unconfigured machines are affected.

**Cause:** The GPO was linked at `DC=lab,DC=local` (domain root) instead of `OU=Workstations,DC=lab,DC=local`. Domain-root links apply to every OU in the domain including Domain Controllers.

**Fix:**
```powershell
# Remove domain-root link
Remove-GPLink -Name "SmartCard Policy" -Target "DC=lab,DC=local"

# Link to Workstations OU only
New-GPLink -Name "SmartCard Policy" -Target "OU=Workstations,DC=lab,DC=local"

# Safety check — confirm no domain-root link exists
(Get-GPInheritance -Target "DC=lab,DC=local").GpoLinks |
    Where-Object { $_.DisplayName -like "*SmartCard*" }
```

**Prevention:** Always scope smart card enforcement GPOs to `OU=Workstations` or a pilot OU. Never link to domain root. The `Enforce-SmartCard.ps1` script does NOT link the GPO — do not link it manually at domain root.

---

### Set-GPRegistryValue fails — "cannot find path" or "path does not exist"

**Symptom:** `Set-GPRegistryValue` throws an error about a path not existing even though the GPO exists in AD.

**Cause:** The SYSVOL folder for the GPO was deleted (or never created). The GPO record exists in AD but there is no corresponding folder in SYSVOL. `Set-GPRegistryValue` needs the SYSVOL folder structure.

**Fix:**
```powershell
$guid    = "{0C180747-4BC1-431F-A877-81779AA8E474}"   # SmartCard Policy GUID
$polBase = "C:\Windows\SYSVOL\domain\Policies\$guid"

# Create the folder structure
New-Item -ItemType Directory -Path "$polBase\Machine" -Force | Out-Null
New-Item -ItemType Directory -Path "$polBase\User"    -Force | Out-Null

# Create the required GPT.ini
@"
[General]
Version=0
displayName=New Group Policy Object
"@ | Out-File "$polBase\GPT.ini" -Encoding ascii -Force

# Now Set-GPRegistryValue will work
Set-GPRegistryValue -Name "SmartCard Policy" -Key "HKLM\..." -ValueName "..." -Type DWord -Value 1
```

**Note:** Use `C:\Windows\SYSVOL\domain\Policies` — NOT `C:\Windows\SYSVOL\sysvol\lab.local\Policies`. The `sysvol\lab.local` path is a junction that may not resolve correctly.

---

### GPO GUID — SmartCard Policy

For reference: the SmartCard Policy GPO GUID in this lab is `{0C180747-4BC1-431F-A877-81779AA8E474}`.

To look up any GPO's GUID:
```powershell
Get-GPO -Name "SmartCard Policy" | Select-Object DisplayName, Id
```

---

## Active Directory & Domain

### Get-ADComputer returns no results — computer not found

**Symptom:** `Get-ADComputer -Filter "Name -eq 'Lab-Workstation01'"` returns nothing.

**Possible causes:**
1. The computer name is longer than 15 characters. NetBIOS truncates names. Search for the truncated name instead:
   ```powershell
   Get-ADComputer -Filter "Name -like 'LAB-WORKSTAT*'"
   ```
2. The computer account was deleted from AD (e.g., after DSRM recovery work). Domain rejoin required.
3. The computer hasn't finished rebooting after joining. Wait 2-3 minutes and retry.

**NetBIOS 15-character limit:** Windows truncates computer names to 15 characters for NetBIOS. `Lab-Workstation01` (17 chars) becomes `LAB-WORKSTATION` (15 chars) in AD. Always verify the actual registered name.

---

### Computer account lands in default Computers container instead of Workstations OU

**Symptom:** After domain join, the computer appears at `CN=LAB-WORKSTATION,CN=Computers,DC=lab,DC=local` instead of `OU=Workstations`.

**Fix A — Prevent at join time:** Use `-OUPath` in `Add-Computer`:
```powershell
Add-Computer -DomainName "lab.local" `
    -Credential (Get-Credential "LAB\Administrator") `
    -OUPath "OU=Workstations,DC=lab,DC=local" `
    -Restart -Force
```

**Fix B — Configure default redirect for all future joins:**
```powershell
redircmp "OU=Workstations,DC=lab,DC=local"
```
Run once on DC01. All computers that join without an explicit `-OUPath` will land in Workstations OU automatically.

**Fix C — Move existing account:**
```powershell
Get-ADComputer "LAB-WORKSTATION" |
    Move-ADObject -TargetPath "OU=Workstations,DC=lab,DC=local"
```

---

## SYSVOL & GPO Infrastructure

### SYSVOL junction path vs. real path

| Path | Type | Notes |
|---|---|---|
| `C:\Windows\SYSVOL\sysvol\lab.local\Policies` | Junction | Does NOT resolve when VHDX is mounted offline. Unreliable. |
| `C:\Windows\SYSVOL\domain\Policies` | Real directory | Always use this path. Works online and offline. |

---

### AD DS will not start in DSRM

**Symptom:** After booting into DSRM, `Start-Service NTDS` fails with "The service did not report an error" or similar. Setting `Repl Perform Initial Synchronizations = 0` does not help.

**Cause:** In this single-DC lab configuration, AD DS cannot start in DSRM.

**Workaround:** Use DSRM only for offline registry edits and file access. Log in as DSRM local admin (`.\Administrator`). For AD operations, boot normally and use the CardIssuer break-glass account.

---

## Workstation Domain Join

### Add-Computer fails — "The specified domain either does not exist or could not be contacted"

**Symptom:** `Add-Computer -DomainName "lab.local"` fails with domain not found, even though ping to DC01 succeeds.

**Cause:** The workstation DNS is pointing to a public DNS server (e.g., 8.8.8.8) instead of DC01. Ping works because it uses the IP directly; domain join requires DNS resolution of `lab.local`.

**Fix:**
```powershell
# Set DNS to DC01
$adapter = Get-NetAdapter | Where-Object {$_.Status -eq "Up"} | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses "10.10.10.10"

# Verify
Resolve-DnsName lab.local
```

DC01's IP in this lab is `10.10.10.10`.

---

### Domain rejoin required after DSRM/recovery work

**Symptom:** WS01 can reach the network but cannot authenticate to the domain. Event log shows "The trust relationship between this workstation and the primary domain failed."

**Cause:** The computer account was deleted from AD during recovery operations, or the machine account password is out of sync.

**Fix:** Log in as `.\Administrator` (local account) and rejoin:
```powershell
Remove-Computer -WorkgroupName "WORKGROUP" -Force -PassThru

Add-Computer -DomainName "lab.local" `
    -Credential (Get-Credential "LAB\Administrator") `
    -OUPath "OU=Workstations,DC=lab,DC=local" `
    -Restart -Force
```

---

## SCAP / Compliance Checker

### SCC results location

SCC 5.10.2 saves results to:
```
C:\Users\Administrator\SCC\Sessions\<timestamp>\Results\
```
NOT `C:\Users\Administrator\SCC\Results\` and NOT `C:\SCC\Results\`.

The `C:\SCC\` folder is used for manually staged ZIPs and the SCC content bundle — it is not the live results output folder.

After a scan, copy results with:
```powershell
$session = "2026-05-28_113752"   # replace with actual timestamp
Copy-Item "C:\Users\Administrator\SCC\Sessions\$session" `
    -Destination "C:\CAC-Lab-Kit-20260526\Lab-Kit\05-Compliance\After-MFA\DC01\" `
    -Recurse -Force
```

---

### After-MFA file exists as a file, not a folder

**Symptom:** `New-Item -ItemType Directory` fails because `After-MFA` already exists as a file (590 KB).

**Cause:** A previous SCC results ZIP was saved directly as `After-MFA` without a `.zip` extension.

**Fix:**
```powershell
$base = "C:\CAC-Lab-Kit-20260526\Lab-Kit\05-Compliance"
Rename-Item -Path "$base\After-MFA" -NewName "After-MFA-WS01-2026-05-27.zip"
New-Item -ItemType Directory -Path "$base\After-MFA\DC01" -Force | Out-Null
New-Item -ItemType Directory -Path "$base\After-MFA\WS01" -Force | Out-Null
```

---

### Get-ChildItem on "C:\Program Files\SCAP Compliance Checker" — access denied

**Symptom:** Searching `C:\Program Files\SCAP Compliance Checker` recurse throws "Access to the path 'C:\Program Files\Windows Defender Advanced Threat Protection\...' is denied."

**Cause:** `-Recurse` walks ALL of `C:\Program Files`, hitting the Defender ATP folder. The search scope is too broad.

**Fix:** Target the exact SCC version folder and suppress errors:
```powershell
Get-ChildItem "C:\Program Files\SCAP Compliance Checker 5.10.2" `
    -Recurse -Filter "*.html" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 5 FullName, LastWriteTime
```

---

## General Windows / PowerShell

### Registry edit fails — "Requested registry access is not allowed"

**Symptom:** `Set-ItemProperty` on `HKLM:\SYSTEM\CurrentControlSet\Services\gpsvc` fails with access denied even as Administrator.

**Cause:** Service registry keys have restrictive ACLs that block even local admins.

**Workaround:** Use `regedit.exe` as TrustedInstaller (via PsExec), or address the root problem at the GPO level instead of the registry key level. For this lab, fixing the GPO is always the right approach.

---

### NetBIOS computer name limit — 15 characters

Windows NetBIOS names are limited to 15 characters. Names longer than 15 characters are silently truncated.

- `Lab-Workstation01` (17 chars) → `LAB-WORKSTATION` in AD
- Always use names ≤ 15 characters for new lab VMs

---

*Last updated: 2026-06-01*
*Add new entries at the top of the relevant section.*
