# Lab-Kit / 03-DomainController

**Author:** Glenn Byron
**Run these scripts on:** Lab-DC01 — the domain controller and Enterprise Issuing CA VM.

---

## Scripts in This Folder

Run in the order listed. Each script sets up what the next one needs.

| # | Script | What it does | NIST Control |
|---|--------|-------------|--------------|
| 1 | `Build-CAC-Lab.ps1` | Installs the AD DS role and promotes the VM to a domain controller for `lab.local`. Triggers a reboot. | IA-2 |
| 2 | `Build-CA-GPO.ps1` | Installs the Enterprise Issuing CA, creates and links the smart card enforcement GPO (`scforceoption=1`, `ScRemoveOption=1`). Run after reboot from step 1. | IA-2(11), AC-11 |
| 3 | `New-CertificateTemplates.ps1` | Creates SmartCardLogon and AdminSmartCardLogon certificate templates on the Issuing CA using PSPKI. Includes a manual fallback guide. | SC-17, IA-5 |
| 4 | `Set-OCSPResponder.ps1` | Installs the Windows Online Responder role, requests an OCSP signing cert, and updates the CA's AIA extension with the OCSP URL. | SC-17, IA-5(2) |
| 5 | `New-TokenEnrollment.ps1` | Two-phase smart card enrollment ceremony. Run in `-Mode RA` first (Registration Authority — identity verification), then `-Mode Issuer` from a different account (Card Issuer — cert enrollment). Blocks the same account from completing both phases. | AC-5, IA-2, IA-5 |
| 6 | `New-YubiKeyToken.ps1` | YubiKey PIV provisioning. Generates AES-256 management key, sets PIN/PUK, generates keys in PIV slots, submits CSR to the CA, imports the cert, and writes an audit log (EventID 7200). | AC-5, IA-2, IA-5 |
| 7 | `Set-AuditLogForwarding.ps1` | Configures Advanced Audit Policy for all Kerberos, Logon, and AD CS subcategories. Sets up Windows Event Forwarding subscriptions to pull Event IDs 4624, 4768, 4886–4890, and others to a central collector. | AU-2, AU-9, AU-12 |
| 8 | `Monitor-PKIHealth.ps1` | PKI health monitor. Checks CRL validity windows, OCSP reachability, CA and smart card cert expiry. Outputs a color-coded dashboard. Run anytime, or schedule as a recurring task. | CA-7, SC-17 |

---

## Run Order

```
Build-CAC-Lab.ps1              ← promotes DC, triggers reboot
  [reboot]
Build-CA-GPO.ps1               ← Issuing CA + smart card GPO
New-CertificateTemplates.ps1   ← SmartCardLogon and Admin cert templates
Set-OCSPResponder.ps1          ← OCSP role and signing cert (optional but recommended)
New-TokenEnrollment.ps1        ← enrollment ceremony (RA phase, then Issuer phase)
New-YubiKeyToken.ps1           ← YubiKey provisioning (if using YubiKeys)
Set-AuditLogForwarding.ps1     ← audit policy and WEF
Monitor-PKIHealth.ps1          ← confirm PKI is healthy before scanning
```

---

## Prerequisites

Before running anything in this folder:

- Run everything as **Administrator** inside the VM
- Scripts are transferred from the Hyper-V host via PowerShell Direct — see `Lab-Kit/01-HyperV-Host/README.md`
- `New-CertificateTemplates.ps1` requires the **PSPKI** PowerShell module. Lab-DC01 uses
  the LabInternal switch (no internet), so `Install-Module` will not work from inside the VM.
  Download PSPKI on the Hyper-V host and copy it in via PowerShell Direct **before** running
  `New-CertificateTemplates.ps1`:
  ```powershell
  # On the Hyper-V host:
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
- **Note:** `New-CertificateTemplates.ps1` uses ADSI directly to duplicate templates (not
  `Copy-CertificateTemplate` — that cmdlet does not exist in PSPKI). PSPKI is used only for
  ACL assignment and publishing to the CA. Any PSPKI version works.

### ⚠️ BREAK GLASS — SMART CARD ENFORCEMENT AND DC LOCKOUT WARNING

> **WARNING — READ THIS BEFORE RUNNING ANY SMART CARD ENFORCEMENT SCRIPTS ON Lab-DC01**

**DO NOT SET `scforceoption=1` IN THE REGISTRY ON Lab-DC01.**

Setting `scforceoption=1` in `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`
(or in `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon`) on a Domain Controller
**LOCKS OUT ALL PASSWORD-BASED LOGIN** — including the Hyper-V console, PowerShell Direct,
and RDP. You will be completely unable to log in without a physical smart card enrolled for
that account.

**SMART CARD ENFORCEMENT BELONGS ON Lab-Workstation01 ONLY — NEVER ON Lab-DC01.**

The DC must retain password-based "break glass" access so you can administer it when
smart card infrastructure is unavailable or broken.

---

**BREAK GLASS — Emergency Access for Lab-DC01**

If you are locked out of Lab-DC01 (console says "You must use Windows Hello or a smart
card to sign in"), recover using one of these methods:

**METHOD 1 — DSRM (Directory Services Repair Mode)**
```
On Hyper-V host:
  Stop-VM -Name "Lab-DC01"
  Start-VM -Name "Lab-DC01"
  (spam F8 the moment the VM connection window goes black)
  Select: Directory Services Repair Mode

Log in with the DSRM LOCAL account (NOT domain):
  Username : .\Administrator
  Password : <LAB-ADMIN-PASSWORD>

Then remove the lockout:
  $p = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System"
  Remove-ItemProperty -Path $p -Name "scforceoption"  -Force
  Remove-ItemProperty -Path $p -Name "ScRemoveOption" -Force
  Restart-Computer -Force
```

**METHOD 2 — Offline VHDX Registry Edit (if F8 timing fails)**
```powershell
# Run on Hyper-V HOST as Administrator
Stop-VM -Name "Lab-DC01" -TurnOff -Confirm:$false
while ((Get-VM "Lab-DC01").State -ne "Off") { Start-Sleep 1 }

$vhdPath = (Get-VM "Lab-DC01" | Get-VMHardDiskDrive | Select-Object -First 1).Path
$drivesBefore = (Get-PSDrive -PSProvider FileSystem).Name
Mount-VHD -Path $vhdPath
$driveLetter = (Get-PSDrive -PSProvider FileSystem).Name |
    Where-Object { $_ -notin $drivesBefore } |
    Where-Object { Test-Path "${_}:\Windows\System32" } | Select-Object -First 1

reg load "HKLM\TempDC" "${driveLetter}:\Windows\System32\config\SOFTWARE"
Remove-ItemProperty "HKLM:\TempDC\Microsoft\Windows\CurrentVersion\Policies\System" -Name "scforceoption"  -Force -ErrorAction SilentlyContinue
Remove-ItemProperty "HKLM:\TempDC\Microsoft\Windows\CurrentVersion\Policies\System" -Name "ScRemoveOption" -Force -ErrorAction SilentlyContinue
Remove-ItemProperty "HKLM:\TempDC\Microsoft\Windows NT\CurrentVersion\Winlogon"      -Name "scforceoption"  -Force -ErrorAction SilentlyContinue
Remove-ItemProperty "HKLM:\TempDC\Microsoft\Windows NT\CurrentVersion\Winlogon"      -Name "ScRemoveOption" -Force -ErrorAction SilentlyContinue
[GC]::Collect(); [GC]::WaitForPendingFinalizers()
reg unload "HKLM\TempDC"
Dismount-VHD -Path $vhdPath
Start-VM -Name "Lab-DC01"
```

---

### Network Adapter — Use Internal Switch, Not External

`Build-CAC-Lab.ps1` fails with `"TCP/IP networking protocol must be properly configured"`
if the VM's adapter is **Disconnected**. An External switch bound to a physical NIC that
has no link (e.g. host uses WiFi, or NIC is unplugged) will leave the VM adapter
disconnected and `Install-ADDSForest` will refuse to promote.

**Fix — use a Hyper-V Internal switch instead (do this once on the Hyper-V host):**

```powershell
New-VMSwitch -Name "LabInternal" -SwitchType Internal
Connect-VMNetworkAdapter -VMName "Lab-DC01"        -SwitchName "LabInternal"
Connect-VMNetworkAdapter -VMName "Lab-Workstation01" -SwitchName "LabInternal"
```

An Internal switch is always Up regardless of physical NIC state. VMs can reach each
other and the Hyper-V host through it — no internet required for this lab.

**Then set the static IP and run the build in one command (from the Hyper-V host):**

```powershell
$cred = Get-Credential   # Administrator / <LAB-ADMIN-PASSWORD>
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

Type the DSRM password (`<LAB-ADMIN-PASSWORD>`) when prompted. The server reboots automatically
when promotion completes. After reboot log in as **LAB\Administrator**.

---

## Key Parameters

**`Build-CAC-Lab.ps1`**
```powershell
.\Build-CAC-Lab.ps1 -DomainName "lab.local" -NetBIOSName "LAB"
```

**`New-TokenEnrollment.ps1`** — run twice, from two different accounts
```powershell
# Phase 1: Registration Authority (identity verification)
.\New-TokenEnrollment.ps1 -Mode RA -UserPrincipalName target@lab.local

# Phase 2: Card Issuer (cert enrollment) — must be a different account
.\New-TokenEnrollment.ps1 -Mode Issuer -UserPrincipalName target@lab.local
```

**`New-YubiKeyToken.ps1`**
```powershell
.\New-YubiKeyToken.ps1 -Mode Provision -UserPrincipalName target@lab.local -CAServer "Lab-DC01"
.\New-YubiKeyToken.ps1 -Mode Verify    -UserPrincipalName target@lab.local
```

**`Monitor-PKIHealth.ps1`**
```powershell
.\Monitor-PKIHealth.ps1 `
    -CRLUrls @("http://pki.lab.local/crl/RootCA.crl","http://pki.lab.local/crl/IssuingCA.crl") `
    -OCSPUrl "http://pki