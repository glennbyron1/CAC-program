# CAC Lab Troubleshooting FAQ

> **This file is sanitized for public distribution.**
> Real lab passwords appear as `<LAB-ADMIN-PASSWORD>`, `<LAB-LABTECH-PASSWORD>`, etc.
> See `.scrub-patterns.example.json` at the repo root for the full pattern list.
> Substitute your own values when running these commands.

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
8. [Common Lab Operations](#common-lab-operations)
9. [Physical Endpoint / Smart Card Enrollment](#physical-endpoint--smart-card-enrollment)

---

## Common Lab Operations

Quick-reference commands for routine tasks. Run all AD commands on **DC01** as `LAB\Administrator`.

---

### Create a new domain user

```powershell
$pw = ConvertTo-SecureString "YourPassword123!" -AsPlainText -Force

New-ADUser `
    -Name            "labtech" `
    -SamAccountName  "labtech" `
    -UserPrincipalName "labtech@lab.local" `
    -GivenName       "Lab" `
    -Surname         "Tech" `
    -AccountPassword $pw `
    -Enabled         $true `
    -PasswordNeverExpires $true `
    -Path            "OU=Workstations,DC=lab,DC=local"

# Confirm
Get-ADUser -Identity labtech | Select-Object Name, UserPrincipalName, Enabled
```

**Set the UPN** — required for certificate enrollment (certreq looks up the user by UPN):
```powershell
Set-ADUser -Identity labtech -UserPrincipalName "labtech@lab.local"
```

**Add to a group:**
```powershell
Add-ADGroupMember -Identity "Domain Admins" -Members "labtech"
```

**Make local admin on a specific machine** (run on that machine):
```powershell
Add-LocalGroupMember -Group "Administrators" -Member "LAB\labtech"
```

**Reset password:**
```powershell
$pw = ConvertTo-SecureString "NewPassword123!" -AsPlainText -Force
Set-ADAccountPassword -Identity labtech -NewPassword $pw -Reset
```

**Disable smart card requirement** (if accidentally set):
```powershell
Set-ADUser -Identity labtech -SmartcardLogonRequired $false
```

---

### List all domain users

```powershell
Get-ADUser -Filter * | Select-Object Name, SamAccountName, Enabled, UserPrincipalName |
    Sort-Object Name | Format-Table -AutoSize
```

---

### Lab user accounts reference

| Account | Password | Role | Notes |
|---|---|---|---|
| `LAB\Administrator` | `<LAB-ADMIN-PASSWORD>` | Domain Admin | Primary admin. Do NOT set SmartcardLogonRequired. |
| `LAB\CardIssuer` | `<LAB-ADMIN-PASSWORD>` | Domain Admin | Break-glass account. Never set SmartcardLogonRequired. |
| `LAB\labtech` | `<LAB-LABTECH-PASSWORD>` | Standard user | Physical laptop test user. Smart card enrollment target. |

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
$pw = ConvertTo-SecureString "<LAB-ADMIN-PASSWORD>" -AsPlainText -Force
Set-ADAccountPassword -Identity Administrator -NewPassword $pw -Reset
Set-ADUser -Identity Administrator -SmartcardLogonRequired $false
```

**Critical warning:** Do NOT run `Set-ADUser -Identity Administrator -SmartcardLogonRequired $true` during normal lab work. This flag persists through reboots, GPO changes, and DSRM recovery. It is independent of all machine-wide settings.

---

### Break-glass accounts — when Administrator is locked out

| Account | Password | Permissions | Notes |
|---|---|---|---|
| `LAB\CardIssuer` | `<LAB-ADMIN-PASSWORD>` | Domain Admins | Primary break-glass. No SmartcardLogonRequired set. Use to fix Administrator. |
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

---

## Physical Endpoint / Smart Card Enrollment

### "Signing in with a security device isn't supported for your account"

**Symptom:** Smart card tile appears at login but clicking it shows "Signing in with a security device isn't supported for your account. Contact your administrator."

**Root cause:** DC01 is missing the **Kerberos Authentication** certificate. Without it, the DC cannot perform PKINIT (Kerberos pre-authentication with certificates), so smart card logon fails at the protocol level before the PIN is even entered.

**Fix — on DC01:**
```powershell
# Publish the template and grant DC auto-enroll rights
Import-Module PSPKI
$t   = Get-CertificateTemplate -Name "KerberosAuthentication"
$acl = $t | Get-CertificateTemplateAcl
$acl | Add-CertificateTemplateAcl -Identity "Domain Controllers" `
       -AccessType Allow -AccessMask Read,Enroll,AutoEnroll | Set-CertificateTemplateAcl

# Enroll directly
certreq -enroll -machine KerberosAuthentication

# Verify — should now show "Kerberos Authentication" EKU
Get-ChildItem Cert:\LocalMachine\My |
    Select-Object Subject, @{N="EKUs";E={$_.EnhancedKeyUsageList.FriendlyName -join ", "}}
```

---

### TightVNC blocks smart card PIN entry

**Symptom:** Smart card tile appears but PIN entry fails or is unresponsive. Login screen shows Windows Hello or smart card error even with correct PIN.

**Cause:** TightVNC and most VNC tools do not support smart card passthrough. The PIN dialog appears on screen but the smart card API cannot be accessed through the VNC session.

**Fix:** Use **RDP (mstsc)** instead of VNC for any machine requiring smart card authentication:
```
mstsc /v:10.10.20.30
```
RDP natively supports smart card forwarding. The PIN prompt works correctly over RDP.

To enable RDP on the endpoint:
```powershell
Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Terminal Server" `
    -Name "fDenyTSConnections" -Value 0
Enable-NetFirewallRule -DisplayGroup "Remote Desktop"
```

---

### Smart card services fail to start — "Cannot open SCardSvr service"

**Symptom:** `Start-Service SCardSvr` fails with "Cannot open SCardSvr service on computer '.'"

**Cause:** The user running the command is not a local administrator. Smart card service management requires elevation.

**Fix:** Ensure the user is a local admin before running service commands, OR log in as `LAB\Administrator` to perform the service setup. The target user (labtech) only needs local admin temporarily during VSC creation and certreq — remove it after enrollment.

If services are stuck after being started (state: running but `certutil -scinfo` still fails):
```powershell
# Force stop and restart the full service chain
Stop-Service ScDeviceEnum, SCardSvr -Force
Start-Sleep 3
Start-Service SCardSvr
Start-Sleep 3
Start-Service ScDeviceEnum
```
If still failing after restart, **reboot the endpoint** — the smart card service stack initializes properly at startup.

---

### Add-CertificateTemplateAcl only adds Read, not Enroll

**Symptom:** After running `Add-CertificateTemplateAcl -AccessMask Read,Enroll`, the ACL check shows only `Read` for the added identity. Certificate requests still fail with `CERTSRV_E_TEMPLATE_DENIED`.

**Cause:** The PSPKI `Add-CertificateTemplateAcl` cmdlet does not reliably write the Certificate Enrollment extended right. It adds the Read ACE but silently drops the Enroll right.

**Fix:** Use the AD PowerShell module to set the extended right directly on the template AD object:
```powershell
$cfgNC = (Get-ADRootDSE).configurationNamingContext
$templateDN = "CN=SmartcardLogon,CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC"
$adAcl = Get-Acl "AD:$templateDN"

# Certificate Enrollment extended right GUID
$enrollGuid = [System.Guid]"0e10c968-78fb-11d2-90d4-00c04f79dc55"
$authUsers  = [System.Security.Principal.SecurityIdentifier]"S-1-5-11"  # Authenticated Users

$ace = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
    $authUsers,
    [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight,
    [System.Security.AccessControl.AccessControlType]::Allow,
    $enrollGuid,
    [System.DirectoryServices.ActiveDirectorySecurityInheritance]::None,
    [System.Guid]::Empty
)
$adAcl.AddAccessRule($ace)
Set-Acl "AD:$templateDN" $adAcl
Restart-Service certsvc
```

---

### vEthernet (External) IP conflicts with vEthernet (LabInternal)

**Symptom:** `New-NetIPAddress` on `vEthernet (External)` fails with "The object already exists" even after removing existing IPs.

**Cause:** `vEthernet (LabInternal)` already owns the 10.10.10.0/24 subnet route. Windows won't assign an IP in the same subnet to a second adapter.

**Fix:** Use a **different subnet** for the External switch. This lab uses:
- LabInternal: 10.10.10.x (VMs only)
- External: 10.10.20.x (physical laptop segment)

Set the External adapter IP using the interface index if the name-based command fails:
```powershell
# Find the interface index
netsh interface ipv4 show interfaces | Select-String "External"

# Set IP using the index number (e.g., index 23)
netsh interface ipv4 set address name=23 static 10.10.20.1 255.255.255.0
```

If DC01 needs to be reachable from the physical segment, add a **second NIC** to DC01 on the External switch rather than moving the existing NIC:
```powershell
# On Hyper-V host (elevated)
Add-VMNetworkAdapter -VMName "Lab-DC01" -SwitchName "External"
# Then set static IP on the new adapter inside DC01 (10.10.20.10)
```

---

### certreq enrolled cert goes to wrong user's store

**Symptom:** Smart card logon fails with "Signing in with a security device isn't supported" even though certutil -scinfo shows the cert. Checking `Cert:\CurrentUser\My` shows the cert is under the wrong user.

**Cause:** `certreq -accept` was run while an admin account was logged in. The private key and cert were generated under the admin's profile, not the target user's. Smart card logon requires the cert to be in the **target user's** personal store.

**Fix:** Log out of the admin account, log in as the **target user**, then re-run all three certreq commands:
```powershell
certreq -f -new C:\Temp\sclogon.inf C:\Temp\sclogon.req
certreq -submit -config "Lab-DC01\LAB-CA" C:\Temp\sclogon.req C:\Temp\sclogon.cer
certreq -accept C:\Temp\sclogon.cer
```
The `-f` flag forces a new request even if a cert for that template already exists.

---

*Last updated: 2026-06-02*
*Add new entries at the top of the relevant section.*
