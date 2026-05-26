# Copyright (c) 2026 Glenn Byron
# Licensed under the MIT License. See LICENSE in the repository root.

<#
.SYNOPSIS
    Creates all three Hyper-V lab VMs for the CAC/PIV ICAM lab environment.

.DESCRIPTION
    Builds the full lab VM set on a Windows Hyper-V host:

      VM 1 — Lab-OfflineRootCA
        Standalone Windows Server 2025 (no network adapter — air-gapped by design).
        Used to host the Offline Root Certificate Authority. Never joins the domain.
        Run Download-OfflineCA-Kit.ps1 output is transferred here via USB or
        PowerShell Direct from the Hyper-V host.

      VM 2 — Lab-DC01
        Windows Server 2025, connected to your lab network switch.
        Becomes the domain controller AND Enterprise Issuing CA.
        Run Build-CAC-Lab.ps1 then Build-CA-GPO.ps1 on this VM.

      VM 3 — Lab-Workstation01 (optional)
        Windows Server 2025 (or Windows 11 if you supply that ISO separately).
        Used to test smart card logon, VPN client, and session-lock behavior.
        Skip with -SkipWorkstation if you already have a workstation VM.

    The script creates a VHDX for each VM and attaches the Windows Server ISO
    so you can boot straight into setup. After OS install, run Unattend-Server.xml
    or Set-VMPostConfig.ps1 to configure each VM before running the CAC scripts.

.PARAMETER VMStoragePath
    Root folder where VM files (VHDX, config) are stored on the Hyper-V host.
    If not specified, the script scans all fixed drives, calculates required space,
    and recommends the best drive — then asks you to confirm before proceeding.
    Typical recommendations: D:\ if it has enough room (keeps VMs off the OS drive);
    otherwise C:\ if D:\ is too small or does not exist.

.PARAMETER ISOPath
    Full path to the Windows Server 2025 ISO file. Defaults to the ISO kept in
    the Lab-Kit folder ("..\Server 2025 Standard.iso" relative to this script).
    Override it if your ISO lives elsewhere. The evaluation ISO is at Microsoft:
    https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2025

.PARAMETER ExternalSwitchName
    Name of the Hyper-V external virtual switch for Lab-DC01 and Lab-Workstation01.
    This switch should have internet or LAN access. Default: "External"
    Create it in Hyper-V Manager > Virtual Switch Manager if it doesn't exist.

.PARAMETER SkipWorkstation
    Skip creating Lab-Workstation01. Use this if you already have a workstation VM
    or are using a physical machine for smart card testing.

.EXAMPLE
    # Create all three VMs using the ISO kept in the Lab-Kit folder (default)
    .\New-LabVMs.ps1

.EXAMPLE
    # Custom storage path and switch name, skip workstation
    .\New-LabVMs.ps1 -ISOPath "..\Server 2025 Standard.iso" `
                     -VMStoragePath 'D:\VMs\CAC-Lab\' `
                     -ExternalSwitchName "LAN" `
                     -SkipWorkstation

.NOTES
    Author         : Glenn Byron
    Run on         : The Hyper-V HOST machine (not inside a VM)
    Requires       : Windows 10/11 Pro or Server with Hyper-V role installed
                     Run as Administrator
    After this     : Boot each VM from ISO, install Windows Server 2025
                     Then run Set-VMPostConfig.ps1 inside each VM
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$VMStoragePath = '',    # Empty = auto-detect and recommend

    [Parameter()]
    [string]$VMFolderName = "HyperV-Lab",   # Subfolder created on the chosen drive

    [Parameter()]
    [string]$ISOPath = (Join-Path $PSScriptRoot "..\Server 2025 Standard.iso"),

    [Parameter()]
    [string]$ExternalSwitchName = "External",

    [Parameter()]
    [switch]$SkipWorkstation
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Drive recommendation — runs when -VMStoragePath is not explicitly provided
# ---------------------------------------------------------------------------
function Select-VMStorageDrive {
    param([long]$RequiredGB, [string]$FolderName = "HyperV-Lab")

    Write-Host ""
    Write-Host "  Scanning drives for VM storage recommendation..." -ForegroundColor Cyan
    Write-Host ""

    # Collect all fixed local drives (DriveType 3 = Fixed)
    $drives = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" |
        Select-Object DeviceID,
            @{N='TotalGB'; E={[math]::Round($_.Size / 1GB, 1)}},
            @{N='FreeGB';  E={[math]::Round($_.FreeSpace / 1GB, 1)}},
            @{N='UsedPct'; E={[math]::Round(100 - ($_.FreeSpace / $_.Size * 100), 0)}} |
        Sort-Object DeviceID

    if (-not $drives) {
        Write-Warning "Could not enumerate drives. Defaulting to C:\$FolderName\"
        return "C:\$FolderName\"
    }

    # Add headroom: VMs need RequiredGB of VHDX space plus ~15 GB for checkpoints/overhead
    $neededGB = $RequiredGB + 15

    # Score each drive:
    #   +2 if it's not the OS drive (C:) — keeps VMs off the system partition
    #   +1 if it has 2x the required space (comfortable headroom)
    #   disqualify if free space < neededGB
    $osDrive = $env:SystemDrive.TrimEnd('\').ToUpper()

    $candidates = foreach ($d in $drives) {
        $letter   = $d.DeviceID.TrimEnd('\').ToUpper()
        $enough   = $d.FreeGB -ge $neededGB
        $score    = 0
        $reasons  = [System.Collections.Generic.List[string]]::new()

        if (-not $enough) {
            $reasons.Add("insufficient space (need $neededGB GB, have $($d.FreeGB) GB)")
        } else {
            if ($letter -ne $osDrive) {
                $score += 2
                $reasons.Add("not the OS drive — better for performance")
            } else {
                $reasons.Add("OS drive — acceptable but not ideal")
            }
            if ($d.FreeGB -ge ($neededGB * 2)) {
                $score += 1
                $reasons.Add("plenty of headroom")
            }
        }

        [PSCustomObject]@{
            Letter   = $letter
            TotalGB  = $d.TotalGB
            FreeGB   = $d.FreeGB
            UsedPct  = $d.UsedPct
            Enough   = $enough
            Score    = $score
            Reasons  = $reasons
        }
    }

    # Print drive table
    $colW = 10
    Write-Host ("  {0,-6} {1,10} {2,10} {3,8}   {4}" -f "Drive","Total GB","Free GB","Used %","Notes") -ForegroundColor White
    Write-Host ("  {0,-6} {1,10} {2,10} {3,8}   {4}" -f "-----","--------","-------","------","-----") -ForegroundColor DarkGray

    foreach ($c in $candidates) {
        $flag  = if (-not $c.Enough) { "[NOT ENOUGH]" } elseif ($c.Letter -eq $osDrive) { "[OS Drive]" } else { "" }
        $color = if (-not $c.Enough) { 'Red' } elseif ($c.Letter -eq $osDrive) { 'Yellow' } else { 'Green' }
        Write-Host ("  {0,-6} {1,10} {2,10} {3,7}%   {4}" -f `
            "$($c.Letter):\", $c.TotalGB, $c.FreeGB, $c.UsedPct, $flag) -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  VMs need approximately $neededGB GB total ($RequiredGB GB VHDX + ~15 GB overhead)." -ForegroundColor White
    Write-Host ""

    # Pick the recommendation: highest-scoring eligible drive
    $best = $candidates | Where-Object { $_.Enough } | Sort-Object Score -Descending | Select-Object -First 1

    if (-not $best) {
        Write-Host "  [!] No drive has enough free space for all VMs ($neededGB GB needed)." -ForegroundColor Red
        Write-Host "      Free up space, add a drive, or reduce VM disk sizes at the top of this script." -ForegroundColor Red
        throw "Insufficient disk space on all available drives."
    }

    $recPath = "$($best.Letter):\$FolderName\"
    $recNote = $best.Reasons -join "; "

    Write-Host "  RECOMMENDATION:  $recPath" -ForegroundColor Cyan
    Write-Host "  Reason        :  $recNote" -ForegroundColor Cyan
    Write-Host ""

    # Let the user confirm or choose a different drive
    Write-Host "  Options:" -ForegroundColor White
    $i = 1
    $eligible = $candidates | Where-Object { $_.Enough }
    foreach ($c in $eligible) {
        $marker = if ($c.Letter -eq $best.Letter) { " <-- recommended" } else { "" }
        Write-Host "    [$i] $($c.Letter):\$FolderName\  ($($c.FreeGB) GB free)$marker" -ForegroundColor White
        $i++
    }
    Write-Host "    [C] Enter a custom path" -ForegroundColor White
    Write-Host ""

    $choice = Read-Host "  Press Enter to accept recommendation, or choose an option"
    $choice = $choice.Trim()

    if ($choice -eq '' -or $choice -eq '1' -and $eligible.Count -eq 1) {
        return $recPath
    }

    if ($choice -match '^\d+$') {
        $idx = [int]$choice - 1
        $picked = @($eligible)[$idx]
        if ($picked) {
            return "$($picked.Letter):\$FolderName\"
        }
    }

    if ($choice -match '^[Cc]$') {
        $custom = Read-Host "  Enter full path (e.g. D:\MyVMs\$FolderName)"
        return $custom.TrimEnd('\') + '\'
    }

    # Default: accept recommendation
    return $recPath
}

# ---------------------------------------------------------------------------
# VM definitions — adjust RAM/disk here if your host is resource-constrained.
# DiskGB is the MAXIMUM size of a DYNAMIC VHDX: the file only grows as space is
# actually used, so real disk consumption is far lower (a fresh Server 2025
# install is ~15-20 GB). These caps are trimmed for a space-constrained host
# while staying above the Server 2025 minimum (32 GB).
# ---------------------------------------------------------------------------
$VMs = @(
    @{
        Name        = "Lab-OfflineRootCA"
        RAM         = 2GB
        CPU         = 2
        DiskGB      = 40
        Networked   = $false   # Air-gapped — no network adapter
        Description = "Offline Root CA - standalone, air-gapped, never domain-joined"
    },
    @{
        Name        = "Lab-DC01"
        RAM         = 4GB
        CPU         = 2
        DiskGB      = 60
        Networked   = $true
        Description = "Domain Controller + Enterprise Issuing CA"
    }
)

if (-not $SkipWorkstation) {
    $VMs += @{
        Name        = "Lab-Workstation01"
        RAM         = 4GB
        CPU         = 2
        DiskGB      = 40
        Networked   = $true
        Description = "Smart card test workstation"
    }
}

# ---------------------------------------------------------------------------
# Drive auto-selection (runs only when -VMStoragePath was not passed)
# ---------------------------------------------------------------------------
$totalDiskGB = ($VMs | Measure-Object -Property DiskGB -Sum).Sum

if ($VMStoragePath -eq '') {
    $VMStoragePath = Select-VMStorageDrive -RequiredGB $totalDiskGB -FolderName $VMFolderName
    Write-Host "  Using: $VMStoragePath" -ForegroundColor Cyan
    Write-Host ""
}

# ---------------------------------------------------------------------------
function Write-Banner {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  HYPER-V LAB VM BUILDER | Author: Glenn Byron" -ForegroundColor Cyan
    Write-Host "  Storage : $VMStoragePath" -ForegroundColor Cyan
    Write-Host "  ISO     : $ISOPath" -ForegroundColor Cyan
    Write-Host "  Switch  : $ExternalSwitchName" -ForegroundColor Cyan
    Write-Host "  VMs     : $($VMs.Count) — total VHDX: $totalDiskGB GB" -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-Step   { param([string]$Msg) Write-Host "[*] $Msg" -ForegroundColor White }
function Write-OK     { param([string]$Msg) Write-Host "  [OK]  $Msg" -ForegroundColor Green }
function Write-Warn   { param([string]$Msg) Write-Host "  [WARN] $Msg" -ForegroundColor Yellow }
function Write-Fail   { param([string]$Msg) Write-Host "  [FAIL] $Msg" -ForegroundColor Red }
function Write-Info   { param([string]$Msg) Write-Host "  [INFO] $Msg" -ForegroundColor DarkGray }

# ---------------------------------------------------------------------------
Write-Banner

# Preflight checks
Write-Step "Running preflight checks..."

# Must run as Administrator
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Fail "This script must be run as Administrator."
    Write-Info "Right-click PowerShell and choose 'Run as Administrator', then try again."
    exit 1
}
Write-OK "Running as Administrator"

# Hyper-V PowerShell module — if Get-VM is missing, the feature isn't installed at all
if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    Write-Fail "Hyper-V is not installed on this machine."
    Write-Host ""
    Write-Host "  Enable it with one of these methods:" -ForegroundColor Cyan
    Write-Host "  Option A — PowerShell (requires reboot):" -ForegroundColor White
    Write-Host "    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -Restart" -ForegroundColor Cyan
    Write-Host "  Option B — Windows Features UI:" -ForegroundColor White
    Write-Host "    Control Panel > Programs > Turn Windows features on or off > Hyper-V" -ForegroundColor Cyan
    Write-Host "  Option C — Server Manager (Server OS):" -ForegroundColor White
    Write-Host "    Add Roles and Features > Hyper-V role" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  NOTE: Hyper-V requires a 64-bit CPU with SLAT and hardware virtualization" -ForegroundColor Yellow
    Write-Host "  enabled in BIOS/UEFI (Intel VT-x or AMD-V). Enable it before installing." -ForegroundColor Yellow
    exit 1
}
Write-OK "Hyper-V PowerShell module found"

# Hyper-V hypervisor service — module can exist even if Hyper-V is only partially configured
$vmms = Get-Service -Name vmms -ErrorAction SilentlyContinue
if (-not $vmms -or $vmms.Status -ne 'Running') {
    Write-Fail "Hyper-V Virtual Machine Management service (vmms) is not running."
    Write-Info "This usually means Hyper-V is installed but the hypervisor is not active."
    Write-Info "Try: Start-Service vmms   (or reboot after enabling Hyper-V)"
    Write-Info "If the service does not exist, re-enable Hyper-V and restart the host."
    exit 1
}
Write-OK "Hyper-V service running"

if (-not (Test-Path $ISOPath)) {
    Write-Fail "ISO not found at: $ISOPath"
    Write-Info "Download Windows Server 2025 evaluation ISO from:"
    Write-Info "https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2022"
    exit 1
}

$switch = Get-VMSwitch -Name $ExternalSwitchName -ErrorAction SilentlyContinue
if (-not $switch) {
    Write-Warn "Virtual switch '$ExternalSwitchName' not found."
    Write-Info "Create it in Hyper-V Manager > Virtual Switch Manager > External."
    Write-Info "Or run: New-VMSwitch -Name '$ExternalSwitchName' -NetAdapterName 'Ethernet' -AllowManagementOS `$true"
    Write-Info "Networked VMs will be skipped until the switch exists."
}

if (-not (Test-Path $VMStoragePath)) {
    Write-Step "Creating VM storage folder: $VMStoragePath"
    New-Item -ItemType Directory -Path $VMStoragePath -Force | Out-Null
    Write-OK "Created $VMStoragePath"
}

Write-OK "Preflight complete"
Write-Host ""

# ---------------------------------------------------------------------------
# Create each VM
# ---------------------------------------------------------------------------
foreach ($vm in $VMs) {
    $name     = $vm.Name
    $vmPath   = Join-Path $VMStoragePath $name
    $vhdxPath = Join-Path $vmPath "$name.vhdx"

    Write-Host "── $name" -ForegroundColor White
    Write-Info $vm.Description

    # Check if VM already exists
    if (Get-VM -Name $name -ErrorAction SilentlyContinue) {
        Write-Warn "VM '$name' already exists — skipping. Delete it first to recreate."
        Write-Host ""
        continue
    }

    # Skip networked VMs if the switch doesn't exist
    if ($vm.Networked -and -not $switch) {
        Write-Warn "Skipping '$name' — external switch '$ExternalSwitchName' not found."
        Write-Host ""
        continue
    }

    if (-not (Test-Path $vmPath)) {
        New-Item -ItemType Directory -Path $vmPath -Force | Out-Null
    }

    # Create VHDX
    Write-Step "Creating VHDX ($($vm.DiskGB)GB): $vhdxPath"
    if ($PSCmdlet.ShouldProcess($vhdxPath, "Create VHDX")) {
        New-VHD -Path $vhdxPath -SizeBytes ($vm.DiskGB * 1GB) -Dynamic | Out-Null
        Write-OK "VHDX created"
    }

    # Create VM (Generation 2, no default VHDX — we attach our own)
    Write-Step "Creating VM: $name"
    if ($PSCmdlet.ShouldProcess($name, "New-VM")) {
        $newVMParams = @{
            Name               = $name
            Path               = $VMStoragePath
            Generation         = 2
            MemoryStartupBytes = $vm.RAM
            NoVHD              = $true
        }
        if ($vm.Networked) {
            $newVMParams['SwitchName'] = $ExternalSwitchName
        }
        New-VM @newVMParams | Out-Null
        Write-OK "VM created"
    }

    # Attach VHDX
    Write-Step "Attaching VHDX..."
    if ($PSCmdlet.ShouldProcess($name, "Add VHDX")) {
        Add-VMHardDiskDrive -VMName $name -Path $vhdxPath
        Write-OK "VHDX attached"
    }

    # Attach ISO to DVD drive
    Write-Step "Attaching ISO: $ISOPath"
    if ($PSCmdlet.ShouldProcess($name, "Attach ISO")) {
        Add-VMDvdDrive -VMName $name -Path $ISOPath
        Write-OK "ISO attached"
    }

    # Configure CPU count
    Set-VMProcessor -VMName $name -Count $vm.CPU

    # Set dynamic memory with min/max bounds
    Set-VMMemory -VMName $name -DynamicMemoryEnabled $true `
        -MinimumBytes 1GB `
        -StartupBytes $vm.RAM `
        -MaximumBytes ($vm.RAM * 2)

    # Set boot order: DVD first (so it boots into Windows setup), then VHDX
    $dvd  = Get-VMDvdDrive -VMName $name
    $disk = Get-VMHardDiskDrive -VMName $name
    Set-VMFirmware -VMName $name -BootOrder $dvd, $disk

    # Disable Secure Boot for lab flexibility (re-enable after OS install if desired)
    Set-VMFirmware -VMName $name -EnableSecureBoot Off

    # Enable guest services (needed for PowerShell Direct / file copy)
    Enable-VMIntegrationService -VMName $name -Name "Guest Service Interface"

    # For air-gapped Root CA: confirm no network adapter
    if (-not $vm.Networked) {
        $adapters = Get-VMNetworkAdapter -VMName $name
        if ($adapters) {
            Write-Step "Removing network adapter from air-gapped VM..."
            $adapters | Remove-VMNetworkAdapter
            Write-OK "Network adapter removed — VM is fully isolated"
        }
        Write-Warn "Root CA VM has NO network adapter by design. Transfer files via PowerShell Direct."
    }

    Write-OK "$name is ready. Boot it to start Windows setup."
    Write-Host ""
}

# ---------------------------------------------------------------------------
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host "  VM BUILD COMPLETE" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor White
Write-Host "  1. Start each VM and boot from the ISO to install Windows Server 2025" -ForegroundColor DarkGray
Write-Host "     Use the Standard (Desktop Experience) edition for the GUI" -ForegroundColor DarkGray
Write-Host "  2. After OS install, run Set-VMPostConfig.ps1 INSIDE each VM" -ForegroundColor DarkGray
Write-Host "     to set hostname, IP, and DNS before running the CAC scripts" -ForegroundColor DarkGray
Write-Host "  3. Transfer files to Lab-OfflineRootCA via PowerShell Direct:" -ForegroundColor DarkGray
Write-Host '     $s = New-PSSession -VMName "Lab-OfflineRootCA" -Credential (Get-Credential)' -ForegroundColor Cyan
Write-Host '     Copy-Item -Path "C:\FedCompliance-Tools" -ToSession $s -Destination "C:\" -Recurse' -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host ""