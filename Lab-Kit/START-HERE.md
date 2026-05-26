# CAC Lab Kit — Start Here

**Author:** Glenn Byron
**What this is:** Everything you need to build and run the CAC/PIV smart card lab from scratch on a Windows Hyper-V host. Follow the steps in order — each phase sets up what the next one needs.

---

## What Gets Built

| VM Name | Role | Network | RAM |
|---------|------|---------|-----|
| Lab-OfflineRootCA | Standalone Root CA — air-gapped, no network adapter | None (isolated) | 2 GB |
| Lab-DC01 | Domain Controller + Enterprise Issuing CA | External switch | 4 GB |
| Lab-Workstation01 | Smart card test endpoint | External switch | 4 GB |

---

## Folder Map

| Folder | Run these on... |
|--------|----------------|
| `01-HyperV-Host/` | Your main Windows machine (the Hyper-V host) |
| `02-OfflineRootCA/` | The Lab-OfflineRootCA VM (air-gapped, no network) |
| `03-DomainController/` | The Lab-DC01 VM (domain controller + issuing CA) |
| `04-Workstation/` | The Lab-Workstation01 VM (smart card test endpoint) |
| `05-Compliance/` | Lab-DC01 (after scanning — stages SCAP reports) |
| `Reference/` | Read these anywhere — checklists and guides |

---

## Prerequisites

Before running anything:

1. **Hyper-V enabled** on your Windows 10/11 Pro or Server host:
   ```powershell
   Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -Restart
   ```

2. **Windows Server 2025 ISO** (evaluation or retail):
   https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025
   Save it to the kit root folder as `Server 2025 Standard.iso`.
   Or pass `-ISOPath` when running `New-LabVMs.ps1` if it lives elsewhere.

3. **An external virtual switch** in Hyper-V for Lab-DC01 and the workstation:
   ```powershell
   New-VMSwitch -Name "External" -NetAdapterName "Ethernet" -AllowManagementOS $true
   ```

4. **Unblock all scripts** — files downloaded from the internet are flagged by Windows as untrusted and
   will be blocked from running. Run this once on the Hyper-V host before starting:
   ```powershell
   Get-ChildItem -Path "C:\CAC-Lab-Kit-20260526" -Recurse -Filter *.ps1 | Unblock-File
   ```
   Only needed on the Hyper-V host. Scripts transferred into VMs via PowerShell
   Direct do not carry the block flag, and `Set-VMPostConfig.ps1` sets
   `RemoteSigned` execution policy inside each VM automatically.

---

## Run Order (if you can not fine files run Get-ChildItem)

### PHASE 1 — Hyper-V Host: Create the VMs

```powershell
cd C:\CAC-Lab-Kit-20260526
cd .\Lab-Kit\01-HyperV-Host\

# Creates all three lab VMs with VHDX disks and ISO attached.
# Script will scan your drives and recommend where to store the VMs.
& .\New-LabVMs.ps1

# Optional: skip the workstation if you already have one
& .\New-LabVMs.ps1 -SkipWorkstation
```

**Verify:** Three VMs appear in Hyper-V Manager: `Lab-OfflineRootCA`, `Lab-DC01`, `Lab-Workstation01`.

---

### PHASE 2 — Download Tools (on the Hyper-V host, internet-connected)

```powershell
# Downloads all tools to C:\FedCompliance-Tools\
& '.\Tools-Kit\Get-LabTools.ps1'

# Or run individually:
& 'Tools-Kit\Download-IssuingCA-Kit.ps1'       # Stages Issuing CA prerequisites + PSPKI
& 'Tools-Kit\Download-FedCompliance-Kit.ps1'   # Downloads SCAP SCC, STIG Viewer, Nessus
```

Then transfer the tools folder to Lab-DC01 (see Phase 5 transfer instructions below).

---

### PHASE 3 — Install Windows on Each VM

1. Start each VM in Hyper-V Manager and connect (double-click > Connect)
2. Boot from the ISO — press any key when prompted
3. Select **Windows Server 2025 Standard (Desktop Experience)**
4. Choose **Custom Install**, select the unallocated disk, let it run
5. Set the Administrator password when prompted

After OS install, open PowerShell as Administrator inside each VM and run
`Set-VMPostConfig.ps1`. Transfer it via PowerShell Direct from the host:

```powershell
# From the Hyper-V host — transfer and run post-config on each VM:
$cred = Get-Credential   # local Administrator on the VM

# Lab-DC01
$s = New-PSSession -VMName "Lab-DC01" -Credential $cred
Copy-Item -Path ".\Set-VMPostConfig.ps1" -ToSession $s -Destination "C:\Scripts\"
Remove-PSSession $s
# Then inside Lab-DC01:
& 'C:\Scripts\Set-VMPostConfig.ps1' -VMRole DomainController -IPAddress 10.10.10.10

# Lab-OfflineRootCA
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred
Copy-Item -Path ".\Set-VMPostConfig.ps1" -ToSession $s -Destination "C:\Scripts\"
Remove-PSSession $s
# Then inside Lab-OfflineRootCA:
& 'C:\Scripts\Set-VMPostConfig.ps1' -VMRole OfflineRootCA

# Lab-Workstation01
$s = New-PSSession -VMName "Lab-Workstation01" -Credential $cred
Copy-Item -Path ".\Set-VMPostConfig.ps1" -ToSession $s -Destination "C:\Scripts\"
Remove-PSSession $s
# Then inside Lab-Workstation01:
& 'C:\Scripts\Set-VMPostConfig.ps1' -VMRole Workstation -IPAddress 10.10.10.20 -DNSServer 10.10.10.10
```

Reboot each VM after the script finishes.

**Verify:** Each VM has correct hostname, static IP is set, and you can ping between VMs.

**Snapshot (from Hyper-V host):**
```powershell
& .\New-LabSnapshot.ps1 -Mode Create -Label "00-BaseOS"
```

---

### PHASE 4 — Offline Root CA

The Root CA VM has no network adapter by design. Transfer files using PowerShell
Direct from the Hyper-V host — this works through the hypervisor with no network needed.

```powershell
# From the Hyper-V host:
$cred = Get-Credential   # local Administrator on Lab-OfflineRootCA
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred
Copy-Item -Path ".\02-OfflineRootCA" `
    -ToSession $s -Destination "C:\" -Recurse
Remove-PSSession $s
```

Then inside `Lab-OfflineRootCA`:
```powershell
& 'C:\02-OfflineRootCA\Initialize-OfflineRootCA.ps1'
```

This runs an 8-step guided ceremony:
1. Air-gap verification (refuses to proceed if network adapter is active)
2. Places and opens CAPolicy.inf for review
3. Installs the AD CS role
4. Configures the Standalone Root CA (4096-bit RSA, SHA-256, 10-year validity)
5. Sets CRL and AIA publication URLs
6. Publishes the initial CRL
7. Exports the Root CA cert and CRL to `C:\OfflineCA-Export\`
8. Prints exact transfer instructions for the next steps

**Verify:** `C:\OfflineCA-Export\` contains a `.cer` and `.crl` file.

Copy the export back to the Hyper-V host:
```powershell
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred
Copy-Item -Path "C:\OfflineCA-Export" -FromSession $s -Destination "C:\CA-Transfer\" -Recurse
Remove-PSSession $s
```

---

### PHASE 5 — Domain Controller Setup (Run in Order)

First, transfer the tools and CA export to Lab-DC01:
```powershell
$cred = Get-Credential   # local Administrator on Lab-DC01
$s = New-PSSession -VMName "Lab-DC01" -Credential $cred
Copy-Item -Path "C:\FedCompliance-Tools" -ToSession $s -Destination "C:\" -Recurse
Copy-Item -Path "C:\CA-Transfer" -ToSession $s -Destination "C:\" -Recurse
Copy-Item -Path ".\03-DomainController" `
    -ToSession $s -Destination "C:\" -Recurse
Remove-PSSession $s
```

Then inside `Lab-DC01`, run these **in order**:

```powershell
# 1. Build the AD domain — reboots automatically when done
& 'C:\03-DomainController\Build-CAC-Lab.ps1'

# --- Wait for the DC to reboot and fully come back up before continuing ---

# 2. Configure the CA and smart card GPO
& 'C:\03-DomainController\Build-CA-GPO.ps1'

# 3. Create smart card certificate templates
& 'C:\03-DomainController\New-CertificateTemplates.ps1'
```

**Snapshot (from Hyper-V host):**
```powershell
& .\New-LabSnapshot.ps1 -Mode Create -Label "01-DomainJoined"
```

```powershell
# 4. Set up OCSP responder (optional — skip if not testing revocation)
& 'C:\03-DomainController\Set-OCSPResponder.ps1' `
    -CAServer "Lab-DC01\Enterprise Issuing CA" `
    -OCSPHostname "ca01.lab.local"

# 5. Configure audit logging
& 'C:\03-DomainController\Set-AuditLogForwarding.ps1' `
    -Mode AuditOnly `
    -CAServerName "Lab-DC01\Enterprise Issuing CA"

# 6. Check PKI health — run this anytime
& 'C:\03-DomainController\Monitor-PKIHealth.ps1'
```

**Verify:** PKI health check passes before moving to enrollment.

**Snapshot (from Hyper-V host):**
```powershell
& .\New-LabSnapshot.ps1 -Mode Create -Label "02-PKI-Ready"
```

---

### PHASE 6 — Smart Card Enrollment

Inside `Lab-DC01`:
```powershell
# Token enrollment ceremony (requires two separate accounts: RA phase then Issuer phase)
# The script blocks you if RA and Issuer are the same account -- this is by design.
& 'C:\03-DomainController\New-TokenEnrollment.ps1'

# YubiKey PIV provisioning (if using YubiKey hardware tokens)
& 'C:\03-DomainController\New-YubiKeyToken.ps1'
```

**Verify:** Smart card certificate issued and visible in `certmgr.msc` on the workstation.

---

### PHASE 7 — Workstation

After `Lab-Workstation01` is domain-joined:
```powershell
& 'C:\04-Workstation\Enforce-SmartCard.ps1'    # Applies smart card GPO
& 'C:\04-Workstation\Deploy-VPNClient.ps1'     # Sets up IKEv2 VPN profile
```

**Verify:** Smart card is required at logon. Workstation locks when card is removed.

---

### PHASE 8 — Compliance Validation and Scanning

**Snapshot before scanning (from Hyper-V host):**
```powershell
& .\New-LabSnapshot.ps1 -Mode Create -Label "03-Before-Scan"
```

Inside `Lab-DC01`:
```powershell
# Run BEFORE the SCAP scan -- 7-layer pass/fail check:
# domain, PKI, smart card, GPO, audit, VPN, recent auth events
# Exports a validation report
& 'C:\05-Compliance\Invoke-LabValidation.ps1'
```

Run the SCAP SCC scan manually (see `Reference\STIG-Hardening-Guide.md`), then:

```powershell
# After scans complete -- moves SCAP SCC results into the right folders
& 'C:\05-Compliance\Stage-Reports.ps1'
```

**Snapshot after scanning:**
```powershell
& .\New-LabSnapshot.ps1 -Mode Create -Label "05-After-Scan"
```

---

## Checkpoint Management

```powershell
cd '.\01-HyperV-Host\'

# List all checkpoints
& .\New-LabSnapshot.ps1 -Mode List

# Restore to a previous state (prompts for confirmation)
& .\New-LabSnapshot.ps1 -Mode Restore -Label "02-PKI-Ready"

# Clean up old checkpoints, keep 5 most recent per VM
& .\New-LabSnapshot.ps1 -Mode Cleanup -Keep 5
```

Recommended checkpoint labels (in phase order):
| Label | When to take it |
|-------|----------------|
| `00-BaseOS` | After OS install and Set-VMPostConfig |
| `01-DomainJoined` | After Build-CAC-Lab.ps1 and reboot |
| `02-PKI-Ready` | After Root CA + Issuing CA configured |
| `03-Before-Scan` | Immediately before SCAP SCC scan |
| `04-After-GPO` | After Build-CA-GPO.ps1 + Enforce-SmartCard.ps1 |
| `05-After-Scan` | After SCAP SCC scan completes |
| `06-Validated` | After Invoke-LabValidation.ps1 passes |

---

## IP Address Reference

| VM | IP | Role |
|----|----|------|
| Lab-DC01 | 10.10.10.10 | Domain Controller, DNS, Issuing CA |
| Lab-Workstation01 | 10.10.10.20 | Test workstation |
| Lab-OfflineRootCA | No IP | Air-gapped |
| Gateway | 10.10.10.1 | Your lab router or host NAT |

---

## Transferring Files to the Offline Root CA

The Offline Root CA has no network adapter by design. All file transfers go through
PowerShell Direct — this tunnels directly through the Hyper-V hypervisor with no
network connection required.

```powershell
# Open a session directly to the VM
$cred = Get-Credential   # local Administrator on Lab-OfflineRootCA
$s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential $cred

# Copy files in
Copy-Item -Path "C:\FedCompliance-Tools" -ToSession $s -Destination "C:\" -Recurse

# Run commands inside the VM without leaving the host
Invoke-Command -Session $s -ScriptBlock { dir C:\FedCompliance-Tools }

# Copy files out (e.g. the Root CA export)
Copy-Item -Path "C:\OfflineCA-Export" -FromSession $s -Destination "C:\CA-Transfer\" -Recurse

Remove-PSSession $s
```

---

## Key Reference Docs

| File | When to use it |
|------|---------------|
| `Reference\LAB-DAY-CHECKLIST.md` | Step-by-step Phase 4 checklist — work through top to bottom |
| `Reference\STIG-Hardening-Guide.md` | How to run SCAP SCC scans and export results |
| `Reference\FedGov-Tools-Setup-Guide.md` | How to install DISA tools (STIG Viewer, Nessus, CSET) |
| `Reference\WatchGuard-IKEv2-VPN-Guide.md` | VPN configuration if testing EAP-TLS |
| `Reference\Blueprint.md` | Full architecture reference |

---

## Quick Reminders

- **Run everything as Administrator** — right-click PowerShell, Run as Administrator
- **Use `&` to run scripts, not `.`** — dot-sourcing breaks `$PSScriptRoot` and causes errors
- **Lab-OfflineRootCA has no network** — all file transfers go via PowerShell Direct
- **Boot order after Build-CAC-Lab.ps1:** it reboots the DC automatically — wait for it to fully come back up before running Build-CA-GPO.ps1
- **Smart card enrollment uses two accounts** — RA phase and Issuer phase must be different people; the script blocks you if they match (separation of duties)
- **Checkpoints consume disk space** — run `New-LabSnapshot.ps1 -Mode Cleanup` periodically

---

*Author: Glenn Byron — Copyright (c) 2026, MIT License*
