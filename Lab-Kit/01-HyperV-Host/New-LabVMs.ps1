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
    Default: C:\HyperV-Lab\

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
                     -VMStoragePath "D:\VMs\CAC-Lab\" `
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
    [string]$VMStoragePath = "C:\HyperV-Lab\",

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
# VM definitions — adjust RAM/disk here if your host is resource-constrained
# ---------------------------------------------------------------------------
$VMs = @(
    @{
        Name        = "Lab-OfflineRootCA"
        RAM         = 2GB
        CPU         = 2
        DiskGB      = 60
        Networked   = $false   # Air-gapped — no network adapter
        Description = "Offline Root CA - standalone, air-gapped, never domain-joined"
    },
    @{
        Name        = "Lab-DC01"
        RAM         = 4GB
        CPU         = 2
        DiskGB      = 80
        Networked   = $true
        Description = "Domain Controller + Enterprise Issuing CA"
    }
)

if (-not $SkipWorkstation) {
    $VMs += @{
        Name        = "Lab-Workstation01"
        RAM         = 4GB
        CPU         = 2
        DiskGB      = 60
        Networked   = $true
        Description = "Smart card test workstation"
    }
}

# ---------------------------------------------------------------------------
function Write-Banner {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host "  HYPER-V LAB VM BUILDER | Author: Glenn Byron" -ForegroundColor Cyan
    Write-Host "  Storage : $VMStoragePath" -ForegroundColor Cyan
    Write-Host "  ISO     : $ISOPath" -ForegroundColor Cyan
    Write-Host "  Switch  : $ExternalSwitchName" -ForegroundColor Cyan
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

if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    Write-Fail "Hyper-V PowerShell module not found. Install Hyper-V role first:"
    Write-Host "    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All" -ForegroundColor Cyan
    exit 1
}

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
    $name    = $vm.Name
    $vmPath  = Join-Path $VMStoragePath $name
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
Write-Host "     Use the Datacenter (Desktop Experience) edition for the GUI" -ForegroundColor DarkGray
Write-Host "  2. After OS install, run Set-VMPostConfig.ps1 INSIDE each VM" -ForegroundColor DarkGray
Write-Host "     to set hostname, IP, and DNS before running the CAC scripts" -ForegroundColor DarkGray
Write-Host "  3. Transfer files to Lab-OfflineRootCA via PowerShell Direct:" -ForegroundColor DarkGray
Write-Host "     `$s = New-PSSession -VMName 'Lab-OfflineRootCA' -Credential (Get-Credential)" -ForegroundColor Cyan
Write-Host "     Copy-Item -Path 'C:\FedCompliance-Tools' -ToSession `$s -Destination 'C:\' -Recurse" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor DarkCyan
Write-Host ""
