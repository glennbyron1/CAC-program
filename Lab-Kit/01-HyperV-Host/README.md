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

4. **Execution policy unblocked** on the Hyper-V host. Scripts cloned from GitHub
   are flagged by Windows as "downloaded from the internet" and will be blocked
   from running. Unblock the entire repo once before running anything:
   ```powershell
   Get-ChildItem 'C:\path\to\CAC-program\' -Recurse -Filter *.ps1 | Unblock-File
   ```
   This removes the block flag from every `.ps1` file in the project without
   changing your system execution policy. You only need to do this once on the
   Hyper-V host — scripts transferred into the VMs via PowerShell Direct do not
   carry the flag, and `Set-VMPostConfig.ps1` sets `RemoteSigned` policy inside
   each VM automatically.

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

## Step 2 — Create an Answer ISO (optional, for hands-free OS install)

**Why an ISO, not a VHDX?**
Windows Setup (windowsPE pass) only scans **removable media** — DVD drives and USB — for
answer files. A SCSI VHDX is a hard disk; Setup ignores it entirely. The answer file must
be delivered on a virtual DVD drive, and the filename must be `autounattend.xml` (not
`unattend.xml`) when placed at the root of that media.

**Before running — edit Unattend-Server.xml:**
- Set the `<ComputerName>` tag to match the VM you are building
  (`Lab-OfflineRootCA`, `Lab-DC01`, or `Lab-Workstation01`)
- The Administrator password is already set in the file. Change it if needed.
- Verify the image index matches your ISO (`dism /Get-WimInfo /WimFile:D:\sources\install.wim`).
  Index 2 = Standard Desktop Experience on most WS2025 media.

**Build the answer ISO and attach it as a second DVD (run on Hyper-V host, VM must be off):**

```powershell
$VMName      = "Lab-DC01"        # change per VM
$UnattendSrc = "C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\Unattend-Server.xml"
$AnswerDir   = "C:\Temp\AnswerISO-Source"
$AnswerISO   = "C:\HyperV-Lab\Answer.iso"

# Stage autounattend.xml (Setup scans for this exact name on removable media)
New-Item -ItemType Directory -Path $AnswerDir -Force | Out-Null
Copy-Item $UnattendSrc "$AnswerDir\autounattend.xml" -Force

# C# helper — PowerShell 5.1 cannot cast COM objects to IStream directly
if (-not ([System.Management.Automation.PSTypeName]'IsoWriter').Type) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public class IsoWriter {
    public static void Write(object comStream, string path) {
        IStream stream = (IStream)comStream;
        using (FileStream fs = File.Create(path)) {
            byte[] buf = new byte[1048576];
            IntPtr pRead = Marshal.AllocHGlobal(4);
            try {
                while (true) {
                    stream.Read(buf, buf.Length, pRead);
                    int n = Marshal.ReadInt32(pRead);
                    if (n == 0) break;
                    fs.Write(buf, 0, n);
                }
            } finally { Marshal.FreeHGlobal(pRead); }
        }
    }
}
'@
}

# Build the ISO using IMAPI2 (no ADK required)
$image = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
$image.FileSystemsToCreate = 3       # Joliet + ISO9660
$image.VolumeName = "ANSWER"
$image.Root.AddTree($AnswerDir, $false)

[IsoWriter]::Write($image.CreateResultImage().ImageStream, $AnswerISO)
Write-Host "Answer ISO built: $AnswerISO" -ForegroundColor Green

# Remove any previous answer ISO from the VM's DVD drives (handles reruns)
Get-VMDvdDrive -VMName $VMName |
    Where-Object { $_.Path -like "*Answer*" } |
    Remove-VMDvdDrive

# Attach the answer ISO as a second DVD drive
Add-VMDvdDrive -VMName $VMName -Path $AnswerISO
Write-Host "Answer ISO attached as DVD drive" -ForegroundColor Green
```

> **Rerunning this script** is safe — it removes the previous answer DVD before re-attaching,
> so you will never get "the disk is already connected" errors.

> **Note:** `Get-VMDvdDrive` does not accept `-ControllerType` as a parameter — filter on
> the returned object properties instead (as shown above). Passing `-ControllerType` directly
> causes a parameter binding error.

`New-LabVMs.ps1` already attaches the Windows Server ISO and sets DVD-first boot order, so
no additional firmware changes are needed after attaching the answer ISO.

**Without the unattend file:** Boot the VM and click through setup manually.
Choose **Windows Server 2025 Standard (Desktop Experience)** for the GUI version.

---

## Step 3 — Install Windows Server on Each VM

**Important — open the VM window BEFORE starting it.** The UEFI DVD boot shows a
"Press any key to boot from CD or DVD..." prompt for about 5 seconds. If the window
isn't open and focused in time, the prompt disappears and the VM reports
"boot loader failed" and skips the DVD entirely.

**Correct sequence:**

1. In Hyper-V Manager, double-click the VM to open the connection window
2. From inside that window: **Action → Start** (or the Start button in the toolbar)
3. The moment the screen shows any activity — **click inside the window and spam Space**
   Keep pressing until the Windows Setup loading screen appears
4. Setup will load — if you attached the answer drive, it runs hands-free from here

**What to expect during unattended install:**

| Phase | What you see | Approx. time |
|-------|-------------|-------------|
| WinPE loads | Blue "Windows Setup" loading screen | ~1 min |
| Disk partitioning | Black screen, no input needed | ~2 min |
| File copy | "Installing Windows" progress bar | ~10 min |
| Specialize + reboots | Several automatic restarts | ~5 min |
| OOBE | Skipped automatically | instant |
| Desktop | Auto-logs in as Administrator | done |

When complete you land at the desktop. The password is whatever you set in
`Unattend-Server.xml` (`AdministratorPassword`).

**If setup starts but shows "Select language settings" (unattend.xml was not picked up):**
The answer drive wasn't attached or wasn't found before setup started. Since Windows hasn't
been written to the VHDX yet it is safe to stop the VM and try again:

```powershell
Stop-VM -Name "Lab-DC01" -Force
```

Then run the answer drive script from Step 2, open the connection window, start the VM from
inside it, and spam Space. Setup will find `unattend.xml` on the answer drive and run
hands-free this time.

**Without the answer drive:** Setup will stop and ask questions. Choose
**Windows Server 2025 Standard (Desktop Experience)**, accept the license,
pick **Custom Install**, select the unallocated disk, and set a password when prompted.
Use the same password as in `Unattend-Server.xml` to keep things consistent.

**If you still see "boot loader failed" after pressing Space:**
```powershell
# Verify Secure Boot is set correctly (must be done while VM is off)
Stop-VM -Name "Lab-DC01" -Force
Set-VMFirmware -VMName "Lab-DC01" -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
# Then re-open the connection window and start from inside it
```

---

## Step 4 — Run Post-Config on Each VM

Once you're at the desktop (setup complete, auto-logged in), transfer and run
`Set-VMPostConfig.ps1` inside each VM. Run this from the **Hyper-V host** — it uses
PowerShell Direct which works without any network connection.

**Transfer script to a VM using PowerShell Direct (from Hyper-V host):**
```powershell
$cred = Get-Credential  # use the VM's local Administrator credentials
$s = New-PSSession -VMName "Lab-DC01" -Credential $cred

# Create the destination folder inside the VM first — New-Item runs on the HOST
# if not wrapped in Invoke-Command, and Copy-Item will fail with "path not found"
Invoke-Command -Session $s -ScriptBlock { New-Item -ItemType Directory -Path "C:\Scripts" -Force | Out-Null }

Copy-Item -Path "C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\Set-VMPostConfig.ps1" `
          -ToSession $s -Destination "C:\Scripts\"
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

## Step 5 — Take a Baseline Snapshot

Before running any CAC scripts, take a checkpoint of each VM at its clean post-config state. This gives you a reliable rollback point if anything goes wrong during the build.

```powershell
# Run from the Hyper-V host
cd C:\path\to\CAC-program\Lab-Kit\01-HyperV-Host\
.\New-LabSnapshot.ps1 -Mode Create -Label "00-BaseOS"
```

The snapshot manager supports Create, List, Restore, Delete, and Cleanup modes. Recommended label sequence as you progress through the lab:

| Label | When to take it |
|-------|----------------|
| `00-BaseOS` | After Set-VMPostConfig.ps1, before any CAC scripts |
| `01-DomainJoined` | After Build-CAC-Lab.ps1 and reboot |
| `02-PKI-Ready` | After Build-CA-GPO.ps1 and CA is operational |
| `03-Before-Scan` | Before running SCAP SCC baseline scan |
| `04-After-GPO` | After applying smart card enforcement GPOs |
| `05-After-Scan` | After both SCAP SCC scans complete |
| `06-Validated` | After Invoke-LabValidation.ps1 confirms all layers pass |

---

## Step 6 — Hand Off to the CAC Scripts

Once all three VMs are configured, rebooted, and snapshotted, you're ready for the CAC lab work:

| VM | Next Script | Location |
|----|------------|----------|
| Lab-DC01 | `Build-CAC-Lab.ps1` | `Lab-Kit\03-DomainController\` |
| Lab-DC01 (after reboot) | `Build-CA-GPO.ps1` | `Lab-Kit\03-DomainController\` |
| Lab-OfflineRootCA | `Initialize-OfflineRootCA.ps1` | `Lab-Kit\02-OfflineRootCA\` (transfer via PowerShell Direct) |
| Lab-Workstation01 | Join domain, then `Enforce-SmartCard.ps1` | `Lab-Kit\04-Workstation\` |

See `Lab-Kit/LAB-DAY-CHECKLIST.md` for the full Phase 4 execution sequence.

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