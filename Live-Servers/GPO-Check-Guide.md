# GPO Compliance Check — How-To Guide

Document ID: LIVE-ICAM-002
Author: Glenn Byron
Framework: NIST SP 800-53 CM-6, CM-7 | DISA RMF CA-7

> **What this guide covers:** How to use `Test-GPOCompliance.ps1` to verify
> that your Group Policy settings are actually applied and active on a server
> or workstation. Covers setup, common checks, reading the output, and
> fixing the problems it finds.

---

## Prerequisites

Before running the script, make sure:

- You are on a **domain-joined machine** (the script can't check domain GPOs on a standalone machine)
- You are running PowerShell **as Administrator**
- The **RSAT Group Policy tools** are installed — the script needs them to look up GPO links

```powershell
# Install RSAT Group Policy Management (if not already there)
Install-WindowsFeature RSAT-Group-Policy-Management

# On Windows 10/11 workstations use this instead:
Add-WindowsCapability -Online -Name "Rsat.GroupPolicy.Management.Tools~~~~0.0.1.0"
```

---

## Basic Usage

```powershell
# Navigate to the Live-Servers folder
cd C:\path\to\CAC-program\Live-Servers\

# Check a GPO by its exact display name
.\Test-GPOCompliance.ps1 -GPOName "SEC-MFA-SmartCard-Enforcement"

# Save the results to a text file at the same time
.\Test-GPOCompliance.ps1 -GPOName "SmartCard Policy" -ExportReport
```

The GPO name must match **exactly** as it appears in Group Policy Management Console (GPMC).
If you are not sure of the name, list all GPOs in the domain:

```powershell
Import-Module GroupPolicy
Get-GPO -All | Select-Object DisplayName, GpoStatus | Sort-Object DisplayName
```

---

## What the Script Checks

For every GPO you name, the script runs three checks in sequence.

### Check 1 — GPO Exists and Is Linked

The script looks up the GPO in Active Directory and confirms:
- The GPO exists with that exact name
- It is enabled (not set to "All Settings Disabled")
- It is linked to at least one OU or container

**If it fails:** The GPO either does not exist, is misnamed, or has not been linked to any OU.
Open GPMC (`gpmc.msc`), find the target OU, right-click it, and choose
**Link an Existing GPO** to attach the GPO.

### Check 2 — GPO Is Applied to This Machine

The script runs `gpresult` and checks whether the GPO appears in the
**Applied GPOs** list for this computer.

**If it fails:** The GPO is linked but not processing on this machine. Common reasons:
- The machine is not in the OU the GPO is linked to
- A **security filter** is excluding this machine (default: Authenticated Users)
- A **WMI filter** on the GPO is evaluating to false
- The GPO processed on a previous refresh but something changed

Fix: run `gpupdate /force`, wait for it to complete, then re-run the script.
For persistent failures, run `gpresult /scope computer /v` and look at the
"Denied GPOs" section for the reason.

### Check 3 — Settings Are Active in the Registry

This is the most important check. A GPO can be linked and show up in gpresult
but still not be doing what you expect if the registry values are wrong.

The script auto-detects the GPO type from its name and runs the right validation:

| GPO name contains | Settings validated |
|-------------------|--------------------|
| SmartCard, MFA, CAC | Smart card enforcement, lock-on-removal, idle timeout |
| Audit, Logging, Event | All 7 audit subcategories, Security log size |
| VPN, IKEv2, Remote | VPN profile, tunnel type, EAP auth, cipher strength |
| Anything else | Dumps all RSoP registry settings from that GPO |

You can override the auto-detection with `-Profile`:

```powershell
# Force smart card profile check even if the GPO name doesn't match
.\Test-GPOCompliance.ps1 -GPOName "My-Custom-Policy" -Profile SmartCard-Enforcement

# Just show me the raw RSoP output for any GPO
.\Test-GPOCompliance.ps1 -GPOName "Default Domain Policy" -Profile Custom
```

---

## Reading the Output

Each check is labeled with one of three statuses:

```
[PASS]  Setting is correct and active
[WARN]  Something is configured but not quite right — worth reviewing
[FAIL]  Setting is missing or wrong — shows the exact fix command below it
```

Example output for a smart card GPO check:

```
── GPO Existence and Link
  [PASS] GPO exists — ID: {a1b2c3d4-...}
         Display Name : SEC-MFA-SmartCard-Enforcement
         Status       : AllSettingsEnabled
         Modified     : 2026-05-10 14:32
  [PASS] GPO enabled — all settings enabled
  [PASS] GPO linked — linked to 2 location(s)
         Link: OU=Workstations,DC=agency,DC=gov (Enabled: True, Enforced: False)
         Link: OU=Servers,DC=agency,DC=gov (Enabled: True, Enforced: False)

── Applied GPO Check (gpresult)
  [PASS] GPO applied to this computer — 'SEC-MFA-SmartCard-Enforcement' found in applied list

── Smart Card GPO Settings Verification
  [PASS] Interactive logon: Require smart card — scforceoption = 1 (ENFORCED)
  [PASS] Interactive logon: Smart card removal behavior — Lock Workstation (1) — CORRECT
  [WARN] Machine inactivity limit — not configured
         Fix: GPO setting: 'Interactive logon: Machine inactivity limit' = 900
  [PASS] Smart Card service (SCardSvr) — running
```

The WARN above means the GPO is working but the idle timeout is not set.
You can fix it in GPMC or by adding the registry value directly and updating the GPO.

---

## Common GPOs to Check — CAC Program

Here are the GPO names used in this program and what each one does:

### Smart Card Enforcement GPO
**Default name:** `SEC-MFA-SmartCard-Enforcement` or `SmartCard Policy`

Enforces hardware token logon and locks the session when the card is pulled.

```powershell
.\Test-GPOCompliance.ps1 -GPOName "SEC-MFA-SmartCard-Enforcement"
```

What it checks:
- `scforceoption = 1` — smart card required for all interactive logons
- `ScRemoveOption = 1` — session locks within 2 seconds of card removal
- `InactivityTimeoutSecs ≤ 900` — idle sessions lock after 15 minutes max
- SCardSvr service is running

### Audit Policy GPO
**Default name:** whatever you named your audit GPO

Enables the audit subcategories that generate the event IDs this program monitors
(4624, 4625, 4768, 4769, 4776, 4886–4890).

```powershell
.\Test-GPOCompliance.ps1 -GPOName "Agency-Audit-Policy" -Profile Audit-Policy
```

What it checks (7 subcategories):
- Logon (4624, 4625)
- Kerberos Authentication Service (4768, 4769)
- Kerberos Service Ticket Operations (4769, 4770)
- Special Logon (4672)
- Certification Services (4886, 4887, 4888)
- Other Account Logon Events (4776)
- Account Lockout (4740)
- Security event log size (recommends ≥ 512 MB)

### VPN Client GPO
**Default name:** whatever you named your VPN GPO

Deploys the IKEv2 VPN profile with EAP-TLS settings to workstations.

```powershell
.\Test-GPOCompliance.ps1 -GPOName "Agency-VPN-Profile" -Profile VPN-Client
```

What it checks:
- VPN connection profile exists
- Tunnel type is IKEv2
- Authentication method includes EAP (certificate-based)
- IPsec cipher is AES-256 (FIPS compliant)

---

## Checking Multiple Machines at Once

The script runs locally on each machine. To check several machines at once,
use PowerShell remoting from a management server:

```powershell
# List of machines to check
$machines = @("workstation01", "workstation02", "dc01", "ca01")

# Copy the script to each machine and run it remotely
foreach ($machine in $machines) {
    $session = New-PSSession -ComputerName $machine -Credential (Get-Credential)

    # Copy the script
    Copy-Item -Path ".\Test-GPOCompliance.ps1" -ToSession $session -Destination "C:\Temp\"

    # Run it and get back a summary
    $result = Invoke-Command -Session $session -ScriptBlock {
        & "C:\Temp\Test-GPOCompliance.ps1" -GPOName "SEC-MFA-SmartCard-Enforcement" -ExportReport
    }

    Remove-PSSession $session
    Write-Host "$machine : done — report saved on that machine"
}
```

Or collect the reports centrally:

```powershell
# Run on remote machine and pull the report file back
Invoke-Command -ComputerName "workstation01" -ScriptBlock {
    & "C:\Scripts\Test-GPOCompliance.ps1" -GPOName "SEC-MFA-SmartCard-Enforcement" -ExportReport
    Get-ChildItem "C:\Scripts\GPO-Report-*.txt" | Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
} | ForEach-Object {
    Copy-Item -Path $_ -FromSession $s -Destination ".\Reports\"
}
```

---

## After Running — What to Do with Failures

| Failure | Quick fix |
|---------|-----------|
| GPO not found | Check the name with `Get-GPO -All \| Select DisplayName`. Names are case-sensitive in some contexts. |
| GPO not applied | `gpupdate /force` — if it still fails, check the machine's OU in AD and the GPO's security filter in GPMC. |
| scforceoption not set | Apply `Enforce-SmartCard.ps1` or check the GPO's Computer Config > Security Options settings in GPMC. |
| ScRemoveOption not set | Same GPO, same section — 'Interactive logon: Smart card removal behavior' should be 'Lock Workstation'. |
| Audit subcategory missing | `auditpol /set /subcategory:"<name>" /success:enable /failure:enable` — or add it to the GPO's audit policy section. |
| Security log too small | `wevtutil sl Security /ms:536870912` (sets to 512 MB). |
| VPN profile not found | Run `Deploy-VPNClient.ps1` on this machine. |

---

## Scheduling Regular Checks

Add this to your maintenance schedule to catch GPO drift — settings that were correct
but changed due to a new GPO, a conflicting policy, or an admin override.

```powershell
# Create a scheduled task that runs the GPO check weekly and emails the report
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument @"
  -NonInteractive -File 'C:\Scripts\Test-GPOCompliance.ps1'
  -GPOName 'SEC-MFA-SmartCard-Enforcement'
  -ExportReport
"@
$trigger  = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Monday -At "07:00"
Register-ScheduledTask -TaskName "GPO Compliance Check" -Action $action `
                        -Trigger $trigger -RunLevel Highest
```

---

*Related: `Test-ServerReadiness.ps1` (full server check), `Install-Guide.md` (deployment steps),*
*`Architecture/STIG-Hardening-Guide.md` (SCAP scanning), `Architecture/Blueprint.md`*
