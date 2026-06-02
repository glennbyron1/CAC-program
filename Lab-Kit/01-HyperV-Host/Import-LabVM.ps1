#Requires -Version 5.1
<#
.SYNOPSIS
    Imports a previously-exported lab VM into Hyper-V, with options to copy
    files to a new location, rename the VM, and reconnect virtual switches.

.DESCRIPTION
    Companion to Export-LabVMs.ps1. Wraps Import-VM with sane defaults:
      - "Copy" mode (default) - copies VHDX/config to a new location, preserving
        the original export. Safe for reuse: import multiple times from one export.
      - "Register" mode - registers the VM in place. The export folder becomes
        the live VM location. Faster but consumes the export.
      - Optional rename so multiple imported copies can coexist.
      - Optional vSwitch reconnect (useful when destination host has different
        switch names than source).

    The script does NOT change domain SID or rename the OS inside the VM.
    If you need an independent clone (different domain), see
    Home-Lab\00-Foundation\VM-Reuse-Workflow.md for the post-import demote/promote
    steps.

.PARAMETER ImportPath
    Path to the exported VM folder (the one containing Virtual Machines\, Virtual Hard Disks\, etc).
    e.g. D:\VM-Exports\LabExport-20260602-1430\Lab-DC01

.PARAMETER DestinationPath
    Where to place the imported VM files. Required for -Copy mode.
    Default: C:\HyperV-Lab\

.PARAMETER NewName
    Optional new display name for the imported VM. If omitted, keeps original name.
    Useful when importing alongside the original (e.g. "Lab-DC01-Clone").

.PARAMETER VMSwitch
    Optional name of an existing vSwitch to attach the imported VM's network adapter(s)
    to. If omitted, the script leaves the imported network adapter(s) as-is (which may
    show "Disconnected" if the source switch doesn't exist on this host).

.PARAMETER RegisterInPlace
    Switch - register the VM in place instead of copying. The export folder becomes
    the live VM location. Cannot be used with -DestinationPath.

.PARAMETER Force
    Switch - overwrite an existing VM with the same name. Use with caution.

.EXAMPLE
    # Default - copy into C:\HyperV-Lab\, keep original name
    .\Import-LabVM.ps1 -ImportPath 'D:\VM-Exports\LabExport-20260602-1430\Lab-DC01'

.EXAMPLE
    # Copy to D:, rename for a Home-Lab Blue Team track
    .\Import-LabVM.ps1 `
        -ImportPath 'D:\VM-Exports\LabExport-20260602-1430\Lab-DC01' `
        -DestinationPath 'D:\HyperV-HomeLab\' `
        -NewName 'HomeLab-DC01' `
        -VMSwitch 'Lab-RedTeam'

.EXAMPLE
    # Register in place - export folder becomes the live VM (single use)
    .\Import-LabVM.ps1 `
        -ImportPath 'D:\VM-Exports\LabExport-20260602-1430\Lab-DC01' `
        -RegisterInPlace

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program
    Last Edit  : 2026-06-02
#>

[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Copy')]
param(
    [Parameter(Mandatory = $true)]
    [string]$ImportPath,

    [Parameter(ParameterSetName = 'Copy')]
    [string]$DestinationPath = 'C:\HyperV-Lab\',

    [string]$NewName,
    [string]$VMSwitch,

    [Parameter(ParameterSetName = 'Register')]
    [switch]$RegisterInPlace,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Helpers ------------------------------------------------------------------
function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

# -- Banner -------------------------------------------------------------------
Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |     CAC Lab Kit - Import a Previously-Exported VM    |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# -- Validate Hyper-V is available --------------------------------------------
if (-not (Get-Command Import-VM -ErrorAction SilentlyContinue)) {
    Write-Fatal 'Hyper-V PowerShell module not available. Run this on a Hyper-V host as Administrator.'
}

# -- Validate import path -----------------------------------------------------
if (-not (Test-Path $ImportPath)) {
    Write-Fatal "Import path not found: $ImportPath"
}

# Find the .vmcx config inside the export
$vmcxFile = Get-ChildItem -Path $ImportPath -Recurse -Filter '*.vmcx' -ErrorAction SilentlyContinue |
    Select-Object -First 1
if (-not $vmcxFile) {
    Write-Fatal "No .vmcx config file found under $ImportPath. Confirm this is a valid Hyper-V export folder."
}
Write-OK "Found VM config: $($vmcxFile.FullName)"

# -- Get a preview of what we're importing ------------------------------------
$compatReport = Compare-VM -Path $vmcxFile.FullName
$importedName = $compatReport.VM.Name
Write-Step "VM to import       : $importedName"
Write-Step "Generation         : $($compatReport.VM.Generation)"
Write-Step "Memory startup     : $([math]::Round($compatReport.VM.MemoryStartup / 1MB)) MB"
Write-Step "Processor count    : $($compatReport.VM.ProcessorCount)"
$adapterCount = @($compatReport.VM.NetworkAdapters).Count
Write-Step "Network adapters   : $adapterCount"

if ($compatReport.Incompatibilities -and $compatReport.Incompatibilities.Count -gt 0) {
    Write-Warn 'Compatibility issues detected:'
    foreach ($issue in $compatReport.Incompatibilities) {
        Write-Info "  - $($issue.Message)"
    }
}
Write-Host ''

# -- Check name conflict ------------------------------------------------------
$finalName = if ($NewName) { $NewName } else { $importedName }
$existing  = Get-VM -Name $finalName -ErrorAction SilentlyContinue
if ($existing) {
    if (-not $Force) {
        Write-Fatal "VM '$finalName' already exists. Use -NewName to rename or -Force to overwrite."
    } else {
        Write-Warn "Force-removing existing VM: $finalName"
        if ($PSCmdlet.ShouldProcess($finalName, 'Remove-VM')) {
            Stop-VM -Name $finalName -Force -ErrorAction SilentlyContinue
            Remove-VM -Name $finalName -Force
        }
    }
}

# -- Perform the import -------------------------------------------------------
Write-Step 'Starting import...'

try {
    if ($RegisterInPlace) {
        Write-Info '  Mode: Register in place (export folder becomes live location)'
        if ($PSCmdlet.ShouldProcess($importedName, 'Import-VM -Register')) {
            $importedVM = Import-VM -Path $vmcxFile.FullName -ErrorAction Stop
        }
    } else {
        Write-Info "  Mode: Copy to $DestinationPath"
        if (-not (Test-Path $DestinationPath)) {
            New-Item -ItemType Directory -Path $DestinationPath -Force | Out-Null
        }
        if ($PSCmdlet.ShouldProcess($importedName, "Import-VM -Copy to $DestinationPath")) {
            $importedVM = Import-VM `
                -Path $vmcxFile.FullName `
                -Copy `
                -GenerateNewId `
                -VirtualMachinePath $DestinationPath `
                -VhdDestinationPath (Join-Path $DestinationPath 'Virtual Hard Disks') `
                -SnapshotFilePath   (Join-Path $DestinationPath 'Snapshots') `
                -SmartPagingFilePath $DestinationPath `
                -ErrorAction Stop
        }
    }
    Write-OK "Imported as: $($importedVM.Name)"
} catch {
    Write-Fatal "Import failed: $($_.Exception.Message)"
}

# -- Rename if requested ------------------------------------------------------
if ($NewName -and $NewName -ne $importedVM.Name) {
    Write-Step "Renaming to: $NewName"
    if ($PSCmdlet.ShouldProcess($importedVM.Name, "Rename-VM -NewName $NewName")) {
        Rename-VM -VM $importedVM -NewName $NewName
        $importedVM = Get-VM -Name $NewName
        Write-OK "Renamed to $NewName"
    }
}

# -- Reconnect vSwitch if requested -------------------------------------------
if ($VMSwitch) {
    Write-Step "Reconnecting network adapter(s) to vSwitch: $VMSwitch"
    $switchExists = Get-VMSwitch -Name $VMSwitch -ErrorAction SilentlyContinue
    if (-not $switchExists) {
        Write-Warn "vSwitch '$VMSwitch' not found on this host. Skipping reconnect."
        Write-Info "Available vSwitches:"
        Get-VMSwitch | ForEach-Object { Write-Info "  - $($_.Name) ($($_.SwitchType))" }
    } else {
        $adapters = @(Get-VMNetworkAdapter -VM $importedVM)
        foreach ($a in $adapters) {
            if ($PSCmdlet.ShouldProcess("$($importedVM.Name) NIC $($a.Name)", "Connect to $VMSwitch")) {
                Connect-VMNetworkAdapter -VMNetworkAdapter $a -SwitchName $VMSwitch
                Write-OK "Connected $($a.Name) -> $VMSwitch"
            }
        }
    }
}

# -- Summary ------------------------------------------------------------------
Write-Host ''
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
Write-Host ("    VM name      : $($importedVM.Name)")              -ForegroundColor Green
Write-Host ("    State        : $($importedVM.State)")             -ForegroundColor Green
Write-Host ("    Path         : $($importedVM.Path)")              -ForegroundColor Green
Write-Host ("    Memory       : $([math]::Round($importedVM.MemoryStartup / 1MB)) MB")  -ForegroundColor Green
Write-Host ("    Processors   : $($importedVM.ProcessorCount)")    -ForegroundColor Green
$disconnected = @(Get-VMNetworkAdapter -VM $importedVM | Where-Object { -not $_.SwitchName })
if ($disconnected.Count -gt 0) {
    Write-Host ("    [!] $($disconnected.Count) network adapter(s) DISCONNECTED - re-run with -VMSwitch to attach") -ForegroundColor Yellow
}
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
Write-Host '  Reminder: this VM keeps its original domain SID. Do NOT run it alongside' -ForegroundColor Yellow
Write-Host '  the original on the same network. See Home-Lab\00-Foundation\VM-Reuse-Workflow.md.' -ForegroundColor Yellow
Write-Host ''
Write-Host '  Done. Start with: Start-VM -Name "' -NoNewline -ForegroundColor Green
Write-Host $importedVM.Name -NoNewline -ForegroundColor White
Write-Host '"' -ForegroundColor Green
Write-Host ''
