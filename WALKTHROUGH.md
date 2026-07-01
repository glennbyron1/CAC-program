# CAC Lab Kit — Step-by-Step Walkthrough

**Author:** Glenn Byron
**Purpose:** Proven, tested build sequence. No unattended install — all Windows
installs are manual click-through. All bugs found during the first full build run
are already fixed in these steps.

---

## Before You Start — Prerequisites

1. **Hyper-V enabled** on your Windows 10/11 Pro or Server host:
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -Restart
   ```

2. **Windows Server 2025 ISO** saved at:
   `C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\Server 2025 Standard.iso`
   (or pass `-ISOPath` to `New-LabVMs.ps1` if yours is elsewhere)

3. **Unblock all scripts** — files from GitHub are flagged as internet downloads and
   will be blocked from running. Run this once on the Hyper-V host:
   ```powershell
   Get-ChildItem -Path "C:\path\to\CAC-program" -Recurse -Filter *.ps1 | Unblock-File
   ```

4. **Fix UTF-8 BOM on all scripts** — PowerShell 5.1 misreads scripts without BOM,
   causing parse errors. Run this once on the Hyper-V host before anything else:
   ```powershell
   Get-ChildItem -Path "C:\path\to\CAC-program" -Recurse -Filter *.ps1 | ForEach-Object {
       $bytes = [System.IO.File]::ReadAllBytes($_.FullName)
       if ($bytes[0] -ne 0xEF) {
           [System.IO.File]::WriteAllBytes($_.FullName, [byte[]](0xEF,0xBB,0xBF) + $bytes)
           Write-Host "BOM added: $($_.Name)" -ForegroundColor Green
       }
   }
   ```

5. **Create a LabInternal virtual switch** — do NOT use External switch. External
   requires a physical NIC with an active link; if your host uses WiFi the VM adapters
   will show Disconnected and domain promotion will fail:
   ```powershell
   New-VMSwitch -Name "LabInternal" -SwitchType Internal
   ```

---

## PHASE 1 — Create the VMs

```powershell
cd C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\
.\New-LabVMs.ps1 -ExternalSwitchName "LabInternal"
```

**Verify:** Three VMs in Hyper-V Manager: `Lab-OfflineRootCA`, `Lab-DC01`, `Lab-Workstation01`.

---

## PHASE 2 — Download Tools

```powershell
cd C:\path\to\CAC-program\Tools-Kit\
.\Get-LabTools.ps1
```

Downloads to `C:\FedCompliance-Tools\`. Takes 5–15 minutes depending on connection.
SCAP SCC requires a manual download from cyber.mil (CAC/ECA required) — see
`C:\FedCompliance-Tools\00-SCAP-SCC\PUT-SCAP-SCC-INSTALLER-HERE.txt`.

---

## PHASE 3 — Install Windows on Each VM

**Do all three VMs the same way. You can run them in parallel.**

### Boot sequence (repeat for each VM):
1. In Hyper-V Manager, **double-click the VM** to open the connection window
2. From inside that window: **Action → Start**
3. The moment any text appears — **click inside the window and spam Space**
4. When Boot Manager appears with "Windows Setup [EMS Enabled]" — press **Enter**
5. Wait through the **white screen (~2 min)** — that is WinPE loading, it is normal

### Click through setup on each VM:
1. Next → **Install now**
2. Select **Windows Server 2025 Standard (Desktop Experience)**
3. Accept license → Next
4. **Custom: Install Windows only**
5. Click the unallocated disk → Next — walks away, installs and reboots automatically
6. Set Administrator password: `<LAB-ADMIN-PASSWORD>`

---

## PHASE 4 — Post-Config Each VM

Run from the **Hyper-V host** after each VM is at the desktop.

> **Important:** Use `Invoke-Command` to create `C:\Scripts` inside the VM.
> Running `New-Item` without it creates the folder on the HOST, causing Copy-Item to fail.

### Lab-DC01:
```powershell
$cred = Get-Credential   # Administrator / <LAB-ADMIN-PASSWORD>
$s = New-PSSession -VMName "Lab-DC01" -Credential $cred
Invoke-Command -Session $s -ScriptBlock { New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null }
Copy-Item -Path "C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\Set-VMPostConfig.ps1" `
          -ToSession $s -Destination "C:\Scripts\"
Remove-PSSession $s
```
Then **inside Lab-DC01**:
```powershell
C:\Scripts\Set-VMPostConfig.ps1 -VMRole DomainController -IPAddress 10.10.10.10
Restart-Computer -Force
```

### Lab-OfflineRootCA:
```powershell
$cred = Get-Credential
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred
Invoke-Command -Session $s -ScriptBlock { New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null }
Copy-Item -Path "C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\Set-VMPostConfig.ps1" `
          -ToSession $s -Destination "C:\Scripts\"
Remove-PSSession $s
```
Then **inside Lab-OfflineRootCA**:
```powershell
C:\Scripts\Set-VMPostConfig.ps1 -VMRole OfflineRootCA
Restart-Computer -Force
```

### Lab-Workstation01:
```powershell
$cred = Get-Credential
$s = New-PSSession -VMName "Lab-Workstation01" -Credential $cred
Invoke-Command -Session $s -ScriptBlock { New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null }
Copy-Item -Path "C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\Set-VMPostConfig.ps1" `
          -ToSession $s -Destination "C:\Scripts\"
Remove-PSSession $s
```
Then **inside Lab-Workstation01**:
```powershell
C:\Scripts\Set-VMPostConfig.ps1 -VMRole Workstation -IPAddress 10.10.10.20 -DNSServer 10.10.10.10
Restart-Computer -Force
```

### Baseline snapshot (after all three rebooted):
```powershell
cd C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\
.\New-LabSnapshot.ps1 -Mode Create -Label "00-BaseOS"
```

---

## PHASE 5 — Offline Root CA Ceremony

### Step 1 — Add loopback adapter (required — AD CS needs a network stack)
```powershell
New-VMSwitch -Name "OfflineCA-Loopback" -SwitchType Private
Add-VMNetworkAdapter -VMName "Lab-OfflineRootCA" -SwitchName "OfflineCA-Loopback"
```

### Step 2 — Transfer scripts to the VM
```powershell
$cred = Get-Credential   # Administrator / <LAB-ADMIN-PASSWORD>
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred
Invoke-Command -Session $s -ScriptBlock { New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null }
Copy-Item -Path "C:\path\to\CAC-program\Lab-Kit\02-OfflineRootCA" `
          -ToSession $s -Destination "C:\Scripts\" -Recurse
Copy-Item -Path "C:\FedCompliance-Tools\09-OfflineRootCA-Kit" `
          -ToSession $s -Destination "C:\" -Recurse
Remove-PSSession $s
```

### Step 3 — Run the ceremony (inside Lab-OfflineRootCA)
```powershell
cd C:\Scripts\02-OfflineRootCA
.\Initialize-OfflineRootCA.ps1
```

- **Step 1 prompt:** type `OVERRIDE` — the Private switch has no external connectivity
- **Step 2 prompt:** press Enter to open CAPolicy.inf in Notepad, review, close, press Enter
- **Step 3:** installs AD CS role — may reboot; re-run script after reboot
- **Step 4:** configures Root CA — takes 1–2 min
- **Steps 5–8:** automated — press Enter at each prompt

### Step 4 — Copy exports and remove loopback (from Hyper-V host)
```powershell
Get-VMNetworkAdapter -VMName "Lab-OfflineRootCA" |
    Where-Object { $_.SwitchName -eq "OfflineCA-Loopback" } |
    Remove-VMNetworkAdapter

$cred = Get-Credential
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred
New-Item -ItemType Directory -Path "C:\CA-Transfer" -Force | Out-Null
Copy-Item -Path "C:\OfflineCA-Export" -FromSession $s -Destination "C:\CA-Transfer\" -Recurse
Remove-PSSession $s
```

**Verify:** `Get-ChildItem C:\CA-Transfer\OfflineCA-Export\` shows `LabRootCA.cer`,
`Lab Root CA.crl`, and `Lab-OfflineRootCA_Lab Root CA.crt`.

**Shut down Lab-OfflineRootCA** — stays off until CRL renewal (every 6 months).

---

## PHASE 6 — Domain Controller Setup

### Step 1 — Transfer scripts and CA files to Lab-DC01
```powershell
$cred = Get-Credential   # Administrator / <LAB-ADMIN-PASSWORD>
$s = New-PSSession -VMName "Lab-DC01" -Credential $cred
Invoke-Command -Session $s -ScriptBlock {
    New-Item -ItemType Directory -Path "C:\Scripts\03-DomainController" -Force | Out-Null
    New-Item -ItemType Directory -Path "C:\CA-Transfer" -Force | Out-Null
}
Copy-Item -Path "C:\path\to\CAC-program\Lab-Kit\03-DomainController" `
          -ToSession $s -Destination "C:\Scripts\" -Recurse -Force
Copy-Item -Path "C:\CA-Transfer\OfflineCA-Export" `
          -ToSession $s -Destination "C:\CA-Transfer\" -Recurse -Force
Remove-PSSession $s
```

### Step 2 — Build the domain (sets static IP then promotes DC)
```powershell
$cred = Get-Credential
Invoke-Command -VMName "Lab-DC01" -Credential $cred -ScriptBlock {
    netsh interface ipv4 set address name="Ethernet" static 10.10.10.10 255.255.255.0 10.10.10.1
    netsh interface ipv4 set dns name="Ethernet" static 127.0.0.1
    $ip = (Get-NetIPAddress -InterfaceAlias "Ethernet" -AddressFamily IPv4).IPAddress
    Write-Host "IP: $ip" -ForegroundColor Cyan
    if ($ip -eq "10.10.10.10") {
        Set-Location "C:\Scripts\03-DomainController"
        .\Build-CAC-Lab.ps1
    }
}
```

- Enter DSRM password when prompted: `<LAB-ADMIN-PASSWORD>`
- Server reboots automatically when domain promotion completes
- DNS delegation warning is normal — ignore it

### Step 3 — After reboot, run Build-CA-GPO.ps1
Log in as **LAB\Administrator** (domain account, not local):
```powershell
$cred = Get-Credential   # LAB\Administrator / <LAB-ADMIN-PASSWORD>
Invoke-Command -VMName "Lab-DC01" -Credential $cred -ScriptBlock {
    Set-Location "C:\Scripts\03-DomainController"
    .\Build-CA-GPO.ps1
}
```

### Step 3b — Create Workstations OU and scope smart card enforcement ⚠️ DO THIS BEFORE DOMAIN JOIN

> **This step must run before Lab-Workstation01 joins the domain.** It creates the
> Workstations OU, redirects new computer accounts into it, and creates the
> `scforceoption=1` GPO scoped to that OU only. Skipping this — or linking the GPO
> at domain root — will lock out Lab-DC01 every time gpupdate runs. The
> `Lab-Kit/Reference/TROUBLESHOOTING.md` "Smart Card / Authentication" section
> documents the recovery, but the prevention is here.

Run on **Lab-DC01** as LAB\Administrator:

```powershell
Import-Module GroupPolicy, ActiveDirectory

$domainDN = (Get-ADDomain).DistinguishedName
$ouDN     = "OU=Workstations,$domainDN"

# 1. Create Workstations OU
New-ADOrganizationalUnit -Name "Workstations" -Path $domainDN -ErrorAction SilentlyContinue
Write-Host "Workstations OU ready: $ouDN" -ForegroundColor Green

# 2. Redirect default computer container - Workstations OU
#    Lab-Workstation01 will land here automatically on domain join
redircmp $ouDN
Write-Host "New computers will land in Workstations OU automatically" -ForegroundColor Green

# 3. Create smart card enforcement GPO (scforceoption=1)
$gpoName = "SEC-MFA-SmartCard-Enforcement"
if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoName -Comment "IA-2(11), AC-11 - Smart card required. Workstations OU only."
}

Set-GPRegistryValue -Name $gpoName `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "scforceoption"       -Type DWord -Value 1

Set-GPRegistryValue -Name $gpoName `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "ScRemoveOption"      -Type DWord -Value 1

Set-GPRegistryValue -Name $gpoName `
    -Key "HKLM\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "InactivityTimeoutSecs" -Type DWord -Value 900

# 4. Link to Workstations OU ONLY - never the domain root
New-GPLink -Name $gpoName -Target $ouDN -LinkEnabled Yes -ErrorAction SilentlyContinue
Write-Host "GPO linked to Workstations OU" -ForegroundColor Green

# 5. Safety check - confirm zero domain-root links
$rootLinks = (Get-GPInheritance -Target $domainDN).GpoLinks
if ($rootLinks | Where-Object { $_.DisplayName -eq $gpoName }) {
    Write-Warning "REMOVE domain-root link NOW - this will lock out DC01!"
    Remove-GPLink -Name $gpoName -Target $domainDN -ErrorAction SilentlyContinue
}

Write-Host "Done - scforceoption=1 scoped to Workstations OU only." -ForegroundColor Cyan
```

> **Why this matters:** `scforceoption=1` applied at domain root hits every machine
> including Lab-DC01, locking out ALL password-based login (console, PowerShell Direct,
> RDP). By putting it on the Workstations OU only, the DC always retains break-glass
> password access. The two-mechanism root cause (machine-wide `scforceoption` vs per-user
> `SmartcardLogonRequired`) and recovery steps are in `Lab-Kit/Reference/TROUBLESHOOTING.md`.

### Step 4 — Install PSPKI module (required — DC has no internet)
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

### Step 5 — Certificate templates
```powershell
$cred = Get-Credential   # LAB\Administrator / <LAB-ADMIN-PASSWORD>
Invoke-Command -VMName "Lab-DC01" -Credential $cred -ScriptBlock {
    Set-Location "C:\Scripts\03-DomainController"
    .\New-CertificateTemplates.ps1
}
```
Type `Lab-DC01` at the `CAServer:` prompt.

### Snapshot:
```powershell
.\New-LabSnapshot.ps1 -Mode Create -Label "01-DomainJoined"
```

---

## PHASE 7 — Workstation

### Step 1 — Set static IP (inside Lab-Workstation01)

DHCP will assign an APIPA address. Fix with netsh before domain join:
```powershell
netsh interface ipv4 set address name="Ethernet" static 10.10.10.20 255.255.255.0 10.10.10.1
netsh interface ipv4 set dns name="Ethernet" static 10.10.10.10
```
The "DNS server is incorrect" warning from the dns command is harmless — setting is applied.

### Step 2 — Transfer scripts (from Hyper-V host)

```powershell
$cred = Get-Credential   # Administrator / <LAB-ADMIN-PASSWORD>  (local)
$s = New-PSSession -VMName "Lab-Workstation01" -Credential $cred
Invoke-Command -Session $s -ScriptBlock { New-Item -ItemType Directory -Path "C:\Scripts\04-Workstation" -Force | Out-Null }
Copy-Item -Path "C:\path\to\CAC-program\Lab-Kit\04-Workstation" `
          -ToSession $s -Destination "C:\Scripts\" -Recurse -Force
Remove-PSSession $s
```

### Step 3 — Domain join (inside Lab-Workstation01)

```powershell
Add-Computer -DomainName "lab.local" -Credential (Get-Credential) -Restart -Force
```
Enter `LAB\Administrator` / `<LAB-ADMIN-PASSWORD>` when prompted. Reboots automatically.

### Step 4 — Apply GPO (inside Lab-Workstation01, after reboot)

Log in as **LAB\Administrator**. The smart card enforcement GPO was already created
by `Build-CA-GPO.ps1` in Phase 6. Pull it with:
```powershell
gpupdate /force
Restart-Computer -Force
```

> **Note:** `Enforce-SmartCard.ps1` in `04-Workstation\` uses `Set-GPRegistryValue`
> (a DC/RSAT cmdlet) — it is NOT a workstation script. GPO is already in place from
> Phase 6. `gpupdate /force` is all that is needed on the workstation.

---

---

> ## ⚠️ WARNING — BREAK GLASS / DO NOT SET scforceoption ON Lab-DC01
>
> **NEVER SET scforceoption=1 IN THE REGISTRY ON Lab-DC01.**
>
> SETTING scforceoption=1 IN `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`
> ON A DOMAIN CONTROLLER LOCKS OUT ALL PASSWORD-BASED LOGIN — INCLUDING THE HYPER-V CONSOLE,
> POWERSHELL DIRECT, AND RDP. YOU WILL BE COMPLETELY LOCKED OUT WITH NO WAY BACK IN WITHOUT
> DSRM OR AN OFFLINE VHDX REGISTRY EDIT.
>
> **SMART CARD ENFORCEMENT (scforceoption=1) BELONGS ON Lab-Workstation01 ONLY.**
>
> THE DC MUST KEEP PASSWORD ACCESS AS A "BREAK GLASS" EMERGENCY PATH.
>
> **IF YOU GET LOCKED OUT OF Lab-DC01 — BREAK GLASS RECOVERY:**
>
> ```powershell
> # METHOD 1: Offline VHDX registry edit (run on Hyper-V HOST)
> Stop-VM -Name "Lab-DC01" -TurnOff -Confirm:$false
> while ((Get-VM "Lab-DC01").State -ne "Off") { Start-Sleep 1 }
> $vhdPath = (Get-VM "Lab-DC01" | Get-VMHardDiskDrive | Select-Object -First 1).Path
> Mount-VHD -Path $vhdPath
> $diskNum = (Get-VHD -Path $vhdPath).DiskNumber
> $part = Get-Partition -DiskNumber $diskNum | Where-Object { $_.Size -gt 5GB } |
>     Sort-Object Size -Descending | Select-Object -First 1
> if (!$part.DriveLetter -or $part.DriveLetter -eq [char]0) {
>     $part | Add-PartitionAccessPath -AssignDriveLetter; Start-Sleep 2
>     $part = Get-Partition -DiskNumber $diskNum -PartitionNumber $part.PartitionNumber
> }
> $dl = $part.DriveLetter
> reg load "HKLM\TempDC" "${dl}:\Windows\System32\config\SOFTWARE"
> Remove-ItemProperty "HKLM:\TempDC\Microsoft\Windows\CurrentVersion\Policies\System" -Name "scforceoption" -Force -ErrorAction SilentlyContinue
> Remove-ItemProperty "HKLM:\TempDC\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "scforceoption" -Force -ErrorAction SilentlyContinue
> [GC]::Collect(); [GC]::WaitForPendingFinalizers()
> reg unload "HKLM\TempDC"
> Dismount-VHD -Path $vhdPath
> Start-VM -Name "Lab-DC01"
> ```
>
> ```
> METHOD 2: DSRM (if you can catch F8 during boot)
> Stop-VM / Start-VM from host → spam F8 → Directory Services Repair Mode
> Username: .\Administrator  |  Password: <LAB-ADMIN-PASSWORD>
> ```
>
> **Validation note:** Invoke-LabValidation.ps1 Layer 4 will show FAIL for scforceoption
> on Lab-DC01. This is expected and acceptable — smart card enforcement is on the workstation.

---

## PHASE 8 — Compliance Scanning

### Step 1 — Snapshot before scanning

```powershell
cd C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\
.\New-LabSnapshot.ps1 -Mode Create -Label "03-Before-Scan"
```

### Step 2 — Run Invoke-LabValidation on Lab-DC01 (inside Lab-DC01)

```powershell
cd C:\Scripts\05-Compliance
.\Invoke-LabValidation.ps1
```

**Expected result:** 16 PASS, 6 WARN, 2 FAIL
- FAIL: `scforceoption` — intentional, DC must not enforce smart card (see break glass warning above)
- FAIL: Time skew ~14400s — false positive; Kerberos actually works (see CHANGELOG)

### Step 3 — Install and run SCC on Lab-DC01

SCC has no internet installer. Transfer via VHDX passthrough or LabTransfer SMB share:

**VHDX passthrough method (reliable, no auth issues):**
```powershell
# On Hyper-V host — create transfer disk, copy SCC zip, attach to DC
$vhdxPath = "C:\Temp\LabTransfer.vhdx"
New-VHD -Path $vhdxPath -SizeBytes 2GB -Dynamic | Out-Null
$disk = Mount-VHD -Path $vhdxPath -PassThru | Get-Disk
Initialize-Disk -Number $disk.Number -PartitionStyle MBR
$part = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
Format-Volume -DriveLetter $part.DriveLetter -FileSystem NTFS -NewFileSystemLabel "LabTransfer" -Confirm:$false | Out-Null
Copy-Item "C:\FedCompliance-Tools\00-SCAP-SCC\*.zip" -Destination "$($part.DriveLetter):\" -Force
Dismount-VHD -Path $vhdxPath
Add-VMHardDiskDrive -VMName "Lab-DC01" -Path $vhdxPath
# Inside Lab-DC01: Get-Disk | Where-Object { $_.OperationalStatus -eq "Offline" } | Set-Disk -IsOffline $false
# Then: (Get-Volume -FileSystemLabel "LabTransfer").DriveLetter — find zip and install SCC
# After install: on host → Remove-VMHardDiskDrive ...
```

**SCC CPE override (required for Windows Server 2025):**
SCC content has CPE for WS2022. When prompted "content is not applicable to this platform":
open Content Details panel → check **"Run content regardless of applicability"** → scan again.

**Run scan** in SCC GUI → Results view shows "Adjusted Score."

### Step 4 — Stage Before-MFA results

**On Lab-DC01** (create zip and push to host share):
```powershell
# Set up LabTransfer account on host first — see CHANGELOG for full commands
net use \\10.10.10.1\LabShare /user:LabTransfer "<LAB-ADMIN-PASSWORD>"
Compress-Archive -Path "C:\Users\Administrator\SCC\Sessions\<session-folder>" `
                 -DestinationPath "C:\SCC\Before-MFA-DC01-Results.zip" -Force
Copy-Item "C:\SCC\Before-MFA-DC01-Results.zip" -Destination "\\10.10.10.1\LabShare\" -Force
net use \\10.10.10.1\LabShare /delete
```

**On Hyper-V host** (move to repo):
```powershell
New-Item -ItemType Directory -Path "C:\path\to\CAC-program\Lab-Kit\05-Compliance\Before-MFA" -Force | Out-Null
Copy-Item "C:\LabShare\Before-MFA-DC01-Results.zip" `
          -Destination "C:\path\to\CAC-program\Lab-Kit\05-Compliance\Before-MFA\" -Force
```

> **Note:** `Stage-Reports.ps1` only works when run on the same machine that ran SCC
> (it reads `%USERPROFILE%\SCC\Results` locally). For DC scans, use the manual zip +
> copy method above instead.

### ✅ COMPLETED — Before-MFA Baselines (Both VMs)

| VM | Score | Session Folder | Staged Zip |
|----|-------|---------------|------------|
| Lab-DC01 | **44.95% [RED]** | `C:\Users\Administrator\SCC\Sessions\2026-05-27_084947\` | `Before-MFA-DC01-Results.zip` |
| Lab-Workstation01 | **42.2% [RED]** | `C:\Users\Administrator.LAB\SCC\Sessions\2026-05-27_092002\` | `Before-MFA-WS01-Results.zip` |

Both staged at: `C:\path\to\CAC-program\Lab-Kit\05-Compliance\Before-MFA\`

Scores are expected — IA-2 smart card controls are not yet enforced. These are the
pre-hardening baselines. The After-MFA scans will show the delta after smart card
enrollment and enforcement is complete.

**Workstation transfer note:** PowerShell Direct works on Lab-Workstation01. Pull
results directly with `Copy-Item -FromSession $s` — no VHDX or SMB workaround needed.
Domain profile path is `C:\Users\Administrator.LAB\SCC\Sessions\` (not `Administrator`).

---

## PHASE 9 — Smart Card Enrollment ✅ COMPLETE

> **Prerequisites before this phase:**
> - ✅ Before-MFA baselines captured for both VMs (DC01: 44.95%, WS01: 42.2%)
> - ✅ PKI chain complete (Root CA → Issuing CA → cert templates)
> - ✅ OCSP responder running

> **Token hardware:**
> This lab uses a **Windows TPM Virtual Smart Card** (vTPM-backed). A physical
> A GIDS smart card was attempted but became PIN-blocked due to a Windows GIDS
> minidriver bug (random admin key — unrecoverable without the card vendor's factory tools).
> See CHANGELOG.md for full details.
>
> **Recommended physical tokens for future runs:**
> - **YubiKey 5 NFC** (~$55, Amazon) — best lab experience, `ykman piv reset` recovers in 2s
> - **HID Crescendo C2300** (~$12/card, HID resellers) — same FIPS 201 chip as gov CAC/PIV

### Step 0 — Pre-Enrollment Setup (Run Once on Lab-DC01)

```powershell
# Set UPNs (built-in Administrator has no UPN by default — script searches by UPN)
Set-ADUser -Identity Administrator -UserPrincipalName "administrator@lab.local"

# Create the CardIssuer account (second person required for AC-5 separation of duties)
$pw = ConvertTo-SecureString "<LAB-ADMIN-PASSWORD>" -AsPlainText -Force
New-ADUser -Name "CardIssuer" -SamAccountName "CardIssuer" `
           -UserPrincipalName "CardIssuer@lab.local" `
           -AccountPassword $pw -Enabled $true -PasswordNeverExpires $true
Add-ADGroupMember -Identity "Domain Admins" -Members "CardIssuer"

# Publish smart card templates to CA
Add-CATemplate -Name "SmartcardLogon"      -Force
Add-CATemplate -Name "SmartCard-AdminLogon" -Force

# Grant Authenticated Users Enroll permission
Import-Module PSPKI
foreach ($name in @("SmartcardLogon", "SmartCard-AdminLogon")) {
    $t   = Get-CertificateTemplate -Name $name
    $acl = $t | Get-CertificateTemplateAcl
    $acl | Add-CertificateTemplateAcl -Identity "Authenticated Users" `
           -AccessType Allow -AccessMask Read, Enroll | Set-CertificateTemplateAcl
    Write-Host "Fixed: $name" -ForegroundColor Green
}

# Set smart card CSPs on the SmartcardLogon template
# (default template does not have card CSPs set — enrolls to software key otherwise)
$cfgNC = (Get-ADRootDSE).configurationNamingContext
$templateDN = "CN=SmartcardLogon,CN=Certificate Templates,CN=Public Key Services,CN=Services,$cfgNC"
Set-ADObject -Identity $templateDN -Replace @{
    pKIDefaultCSPs = @(
        "1,Microsoft Base Smart Card Crypto Provider",
        "2,Microsoft Smart Card Key Storage Provider"
    )
}

# Pre-create audit log file so CardIssuer can write to it
New-Item -Path "C:\Windows\Logs\TokenEnrollment.log" -ItemType File -Force | Out-Null
icacls "C:\Windows\Logs\TokenEnrollment.log" /grant "LAB\CardIssuer:(M)"
```

### Step 0b — Enable vTPM on Lab-Workstation01 (run on Hyper-V host, VM off)

Skip this step if using a physical smart card.

```powershell
Stop-VM "Lab-Workstation01" -Force
Set-VMKeyProtector -VMName "Lab-Workstation01" -NewLocalKeyProtector
Enable-VMTPM -VMName "Lab-Workstation01"
Start-VM "Lab-Workstation01"
# Verify:
(Get-VMSecurity -VMName "Lab-Workstation01").TpmEnabled   # Should return True
```

### Step 0c — Create Virtual Smart Card on Lab-Workstation01

**Must run from Basic Session** — tpmvscmgr fails inside Enhanced Session (RDP).

In Hyper-V VM Connection: **View → Basic Session**. Log in as LAB\Administrator.

```powershell
tpmvscmgr.exe create /name "LabVSC" `
    /pin PROMPT `
    /pinpolicy minlen 6 `
    /adminkey DEFAULT `
    /generate
# Enter PIN: 123456 when prompted
```

Expected output:
```
TPM Smart Card created.
Smart Card Reader Device Instance ID = ROOT\SMARTCARDREADER\0000
```

Verify:
```powershell
certutil -scinfo
# Should show: Microsoft Virtual Smart Card 0 — SCARD_STATE_PRESENT
```

Switch back to Enhanced Session when done: **View → Enhanced Session**.

### Step 1 — RA Phase (run on Lab-DC01 console as LAB\Administrator)

```powershell
cd C:\Scripts\03-DomainController
.\New-TokenEnrollment.ps1 -Mode RA -UserPrincipalName administrator@lab.local
```

Answer Y to all identity checklist items. Enter any values for ID document prompts
(e.g. Passport / US State Dept / Employee Badge). Script sets the RA authorization
flag in AD (`pager` attribute) and prints **"RA PHASE COMPLETE"**.

### Step 2 — Issuer Phase — Part 1 (run as LAB\CardIssuer)

From the Lab-DC01 console, open a CardIssuer window:
```powershell
Start-Process powershell -Credential (Get-Credential "LAB\CardIssuer") `
    -ArgumentList "-NoExit -Command `"cd C:\Scripts\03-DomainController; .\New-TokenEnrollment.ps1 -Mode Issuer -UserPrincipalName administrator@lab.local`""
```

Answer Y to all pre-issuance checklist items.
- Token serial number: `ROOT\SMARTCARDREADER\0000` (VSC instance ID)
- Token type: `TPM Virtual Smart Card`

When the script asks **"Certificate enrolled successfully onto the token? [Y/N]"**
— answer **N** for now and proceed to Step 3.

### Step 3 — Cert Enrollment onto the Virtual Smart Card

On **Lab-Workstation01** (Enhanced Session or Basic Session), logged in as LAB\Administrator:

```powershell
# Create the certreq INF file
@"
[Version]
Signature="`$Windows NT`$"

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
"@ | Out-File "C:\Temp\sclogon.inf" -Encoding ascii

# Generate key (goes into vTPM) and write CSR to disk
certreq -f -new C:\Temp\sclogon.inf C:\Temp\sclogon.req
# Expected output: CertReq: Request Created

# Submit to CA — issues the certificate
certreq -submit -config "Lab-DC01\LAB-CA" C:\Temp\sclogon.req C:\Temp\sclogon.cer

# Install cert — links it to the vTPM key
certreq -accept C:\Temp\sclogon.cer

# Verify — confirm cert is on the virtual card
certutil -scinfo
# Success: "Displayed cert for reader: Microsoft Virtual Smart Card 0"
# Success: "CertUtil: -SCInfo command completed successfully." (no NTE_BAD_KEYSET)
```

> **Note:** `certmgr.msc` shows SmartcardLogon as "Unavailable" — this is a UI
> validation bug in the wizard. The `certreq` INF approach bypasses it and works
> correctly. See CHANGELOG.md for the full diagnosis.

### Step 4 — Complete the Issuer Phase

Back on Lab-DC01 in the CardIssuer window, re-run the Issuer phase:
```powershell
.\New-TokenEnrollment.ps1 -Mode Issuer -UserPrincipalName administrator@lab.local
```

Answer Y to "Certificate enrolled successfully onto the token?"
Enter token serial `ROOT\SMARTCARDREADER\0000` when prompted.

> **Note:** The script will show an error setting `SmartcardLogonRequired` — CardIssuer
> lacks the AD write right for this attribute. Non-fatal; ceremony completes. The
> workstation GPO (`scforceoption=1`) handles enforcement. Do NOT set
> `SmartcardLogonRequired` on the Administrator account — it would block DC console
> access.

### Step 5 — Test Smart Card Logon on Lab-Workstation01

Lock workstation (`Win+L`) → click **Sign-in options** → select the **smart card tile**
(chip icon) → enter PIN `123456` → confirm LAB\Administrator logs in.

Verify Kerberos TGT issued with certificate on Lab-DC01:
```powershell
Get-WinEvent -LogName Security -FilterXPath "*[System[EventID=4768]]" |
    Select-Object -First 5 | Format-List TimeCreated, Message
```

### Step 6 — After-MFA Scans

After smart card logon is confirmed working, repeat SCAP SCC scans on both VMs.
Stage results to `Lab-Kit\05-Compliance\After-MFA\`.

**P