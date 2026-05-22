# Hyper-V Lab Setup

**Author:** Glenn Byron
**Purpose:** Scripts and answer files to build the three-VM Hyper-V lab environment for the CAC/PIV ICAM project.

---

## What Gets Built

| VM Name | Role | Network | RAM |
|---------|------|---------|-----|
| Lab-OfflineRootCA | Standalone Root CA — air-gapped, no network adapter | None (isolated) | 2 GB |
| Lab-DC01 | Domain Controller + Enterprise Issuing CA | External switch | 4 GB |
| Lab-Workstation01 | Smart card test endpoint | External switch | 4 GB |

---

## Prerequisites

Before running anything, make sure you have:

1. **Hyper-V enabled** on your Windows 10/11 Pro or Server host
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -Restart
   ```

2. **Windows Server 2025 ISO** (evaluation or retail) from Microsoft:
   https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025
   This kit keeps the ISO in the Lab-Kit folder as `Server 2025 Standard.iso`
   (it is gitignored, so it never gets pushed). `New-LabVMs.ps1` defaults to
   that path; override `-ISOPath` if yours lives elsewhere.

3. **An external virtual switch** in Hyper-V for Lab-DC01 and the workstation.
   Create it in Hyper-V Manager > Virtual Switch Manager > New > External.
   Or via PowerShell (substitute your real NIC name):
   ```powershell
   New-VMSwitch -Name "External" -NetAdapterName "Ethernet" -AllowManagementOS $true
   ```

---

## Step 1 — Create the VMs (run on Hyper-V host)

```powershell
cd C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\
.\New-LabVMs.ps1                       # uses ..\Server 2025 Standard.iso by default
# or, if your ISO is elsewhere:
.\New-LabVMs.ps1 -ISOPath "D:\ISOs\Server 2025 Standard.iso"
```

This creates all three VMs with VHDX disks, attaches the ISO, and sets the boot order to DVD first. It does NOT start them — that's on you.

Optional parameters:
- `-VMStoragePath "D:\VMs\"` — store VM files on a different drive (default: C:\HyperV-Lab\)
- `-ExternalSwitchName "LAN"` — if your external switch has a different name
- `-SkipWorkstation` — skip creating the workstation VM

---

## Step 2 — Inject the Unattend File (optional, for hands-free OS install)

If you want Windows to install itself without any clicking, inject `Unattend-Server.xml` into each VM's VHDX before first boot.

**Before injecting — edit Unattend-Server.xml:**
- Replace `CHANGE-ME-LAB-PASSWORD` with a real lab admin password
- Change the `<ComputerName>` tag to match each VM (Lab-OfflineRootCA / Lab-DC01 / Lab-Workstation01)

**Inject via PowerShell (run on Hyper-V host, VM must be off):**

```powershell
# Example for Lab-DC01
$vhdxPath = "C:\HyperV-Lab\Lab-DC01\Lab-DC01.vhdx"
$vhd = Mount-VHD -Path $vhdxPath -PassThru
$driveLetter = ($vhd | Get-Disk | Get-Partition | Where-Object { $_.DriveLetter -match '[C-Z]' }).DriveLetter
Copy-Item ".\Unattend-Server.xml" "$($driveLetter):\unattend.xml"
Dismount-VHD -Path $vhdxPath
```

Repeat for each VM, updating the hostname in the XML each time.

**Without the unattend file:** Just boot the VM and click through the Windows setup wizard manually. Choose "Windows Server 2025 Standard (Desktop Experience)" for the GUI version.

---

## Step 3 — Install Windows Server on Each VM

1. In Hyper-V Manager, start each VM and connect to it (double-click > Connect)
2. Boot from the ISO — press any key when prompted
3. Select **Windows Server 2025 Standard (Desktop Experience)**
4. Choose **Custom Install**, select the unallocated disk, and let it run
5. Set the Administrator password when prompted (or it's already set if you used unattend)

---

## Step 4 — Run Post-Config on Each VM

After Windows is installed and you're at the desktop, open PowerShell as Administrator and run `Set-VMPostConfig.ps1` inside each VM. Transfer the script via PowerShell Direct from the host, or copy it manually.

**Transfer script to a VM using PowerShell Direct (from Hyper-V host):**
```powershell
$cred = Get-Credential  # use the VM's local Administrator credentials
$s = New-PSSession -VMName "Lab-DC01" -Credential $cred
Copy-Item -Path ".\Set-VMPostConfig.ps1" -ToSession $s -Destination "C:\Scripts\"
Remove-PSSession $s
```

**Run inside Lab-DC01:**
```powershell
.\Set-VMPostConfig.ps1 -VMRole DomainController -IPAddress 10.10.10.10
```

**Run inside Lab-OfflineRootCA:**
```powershell
.\Set-VMPostConfig.ps1 -VMRole OfflineRootCA
```

**Run inside Lab-Workstation01:**
```powershell
.\Set-VMPostConfig.ps1 -VMRole Workstation -IPAddress 10.10.10.20 -DNSServer 10.10.10.10
```

Reboot each VM after the script finishes.

---

## Step 5 — Hand Off to the CAC Scripts

Once all three VMs are configured and rebooted, you're ready for the CAC lab work:

| VM | Next Script | Location |
|----|------------|----------|
| Lab-DC01 | `Build-CAC-Lab.ps1` | Automation-Scripts\ |
| Lab-DC01 (after reboot) | `Build-CA-GPO.ps1` | Automation-Scripts\ |
| Lab-OfflineRootCA | `Download-OfflineCA-Kit.ps1` output | Transfer via PowerShell Direct |
| Lab-Workstation01 | Join domain, then test smart card login | After DC is up |

See `LAB-DAY-CHECKLIST.md` in the repo root for the full Phase 4 execution sequence.

---

## Transferring Files to the Offline Root CA

The Offline Root CA has no network adapter by design. Transfer files using PowerShell Direct from the Hyper-V host — this works without any network connection, just through the Hyper-V hypervisor:

```powershell
# Open a session directly to the VM (bypasses all networking)
$cred = Get-Credential   # local Administrator on Lab-OfflineRootCA
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred

# Copy the entire Root CA kit into the VM
Copy-Item -Path "C:\FedCompliance-Tools" -ToSession $s -Destination "C:\" -Recurse

# Run commands inside the VM directly
Invoke-Command -Session $s -ScriptBlock {
    dir C:\FedCompliance-Tools
}

Remove-PSSession $s
```

---

## IP Address Reference

| VM | IP | Role |
|----|----|------|
| Lab-DC01 | 10.10.10.10 | Domain Controller, DNS, Issuing CA |
| Lab-Workstation01 | 10.10.10.20 | Test workstation |
| Lab-OfflineRootCA | No IP | Air-gapped |
| Gateway | 10.10.10.1 | Your lab router or host NAT |

These are the defaults in `New-LabVMs.ps1` and `Set-VMPostConfig.ps1`. Change them if your home lab uses a different subnet.

---

*Related: `LAB-DAY-CHECKLIST.md`, `Architecture/STIG-Hardening-Guide.md`, `Architecture/Blueprint.md`*
