#Requires -Version 5.1
<#
.SYNOPSIS
    Reports lab VM disk usage and estimates the resulting export size before
    you commit to running Export-LabVMs.ps1. Non-destructive - read-only.

.DESCRIPTION
    Reads each lab VM's VHDX inventory and snapshot footprint, then estimates
    the export size for both clean (single-state) and with-checkpoints modes.
    Also surveys free space on candidate target drives (default D:) so you
    know up front whether the export will fit.

    Use this BEFORE running Export-LabVMs.ps1 if you want a planning view.
    It does nothing destructive - no VM state changes, no file writes outside
    the optional -ReportPath.

.PARAMETER VMNames
    Array of VM names to inspect. Defaults to Lab-DC01 + Lab-OfflineRootCA
    (same defaults as Export-LabVMs.ps1).

.PARAMETER IncludeWorkstation
    Switch - also inspect Lab-Workstation01. Off by default.

.PARAMETER TargetDrives
    Array of drive letters to check for free space. Defaults to D:.

.PARAMETER ReportPath
    Optional path to write a markdown report file. If omitted, only screen output.

.EXAMPLE
    # Default - DC01 + OfflineRootCA, check D: drive
    .\Get-LabVMSize.ps1

.EXAMPLE
    # Include workstation, check D: and E:
    .\Get-LabVMSize.ps1 -IncludeWorkstation -TargetDrives D, E

.EXAMPLE
    # Save a markdown report alongside the script output
    .\Get-LabVMSize.ps1 -IncludeWorkstation -ReportPath "$env:USERPROFILE\Desktop\Lab-Size-Report.md"

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program
    Last Edit  : 2026-06-02
#>

[CmdletBinding()]
param(
    [string[]]$VMNames     = @('Lab-DC01', 'Lab-OfflineRootCA'),
    [switch]$IncludeWorkstation,
    [string[]]$TargetDrives = @('D'),
    [string]$ReportPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -- Helpers ------------------------------------------------------------------
function Write-Step  { param([string]$msg) Write-Host "  $msg"          -ForegroundColor Cyan   }
function Write-OK    { param([string]$msg) Write-Host "  [OK] $msg"     -ForegroundColor Green  }
function Write-Warn  { param([string]$msg) Write-Host "  [!!] $msg"     -ForegroundColor Yellow }
function Write-Info  { param([string]$msg) Write-Host "       $msg"     -ForegroundColor Gray   }
function Write-Fatal { param([string]$msg) Write-Host "`n  [FATAL] $msg`n" -ForegroundColor Red; exit 1 }

function Format-GB { param([double]$bytes) '{0,7:N1} GB' -f ($bytes / 1GB) }

# -- Banner -------------------------------------------------------------------
Write-Host ''
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host '  |     CAC Lab Kit - VM Size + Export Planning Report   |' -ForegroundColor DarkCyan
Write-Host '  +======================================================+' -ForegroundColor DarkCyan
Write-Host ''

# -- Build final VM list ------------------------------------------------------
if ($IncludeWorkstation -and ($VMNames -notcontains 'Lab-Workstation01')) {
    $VMNames += 'Lab-Workstation01'
}

# -- Validate Hyper-V is available --------------------------------------------
if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    Write-Fatal 'Hyper-V PowerShell module not available. Run this on the Hyper-V host as Administrator.'
}

# -- Inspect each VM ----------------------------------------------------------
$vmReports = @()

foreach ($name in $VMNames) {
    $vm = Get-VM -Name $name -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Warn "VM not found, skipping: $name"
        continue
    }

    Write-Step "Inspecting: $($vm.Name)  (state: $($vm.State))"

    # VHDX disks attached to the VM (current pointer disks)
    $disks = @(Get-VMHardDiskDrive -VM $vm)
    $diskFiles = @()
    $diskBytes = 0
    foreach ($d in $disks) {
        if (Test-Path $d.Path) {
            $fileInfo = Get-Item $d.Path
            $diskFiles += [PSCustomObject]@{
                Path  = $d.Path
                Bytes = $fileInfo.Length
            }
            $diskBytes += $fileInfo.Length
        }
    }

    # Snapshot AVHDX files (live in the same folder, accumulate as parent disks)
    $vmFolder    = Split-Path $vm.Path -Parent
    $avhdxFiles  = @()
    $avhdxBytes  = 0
    if (Test-Path $vmFolder) {
        $avhdxFiles = @(Get-ChildItem -Path $vmFolder -Recurse -Filter '*.avhdx' -ErrorAction SilentlyContinue)
        $avhdxBytes = ($avhdxFiles | Measure-Object Length -Sum).Sum
        if (-not $avhdxBytes) { $avhdxBytes = 0 }
    }

    # Snapshot count
    $snapshots = @(Get-VMSnapshot -VMName $vm.Name -ErrorAction SilentlyContinue)

    # Total folder footprint (everything Hyper-V keeps for this VM)
    $folderBytes = 0
    if (Test-Path $vmFolder) {
        $folderBytes = (Get-ChildItem $vmFolder -Recurse -File -ErrorAction SilentlyContinue |
                        Measure-Object Length -Sum).Sum
        if (-not $folderBytes) { $folderBytes = 0 }
    }

    # Clean export estimate: parent VHDX files only (snapshots merged away)
    # Hyper-V's Export-VM with no checkpoints exports the merged parent VHDX,
    # which is typically the .vhdx file size. avhdx files would be discarded.
    $cleanExportEst = $diskBytes

    # With-checkpoints export estimate: full folder size (every avhdx preserved)
    $withCheckpointsEst = $folderBytes

    $vmReports += [PSCustomObject]@{
        Name              = $vm.Name
        State             = $vm.State
        ProcessorCount    = $vm.ProcessorCount
        MemoryStartupGB   = [math]::Round($vm.MemoryStartup / 1GB, 2)
        DiskCount         = $disks.Count
        DiskBytes         = $diskBytes
        SnapshotCount     = $snapshots.Count
        SnapshotBytes     = $avhdxBytes
        FolderBytes       = $folderBytes
        CleanExportEst    = $cleanExportEst
        WithCheckpointsEst = $withCheckpointsEst
        DiskFiles         = $diskFiles
    }

    Write-Info ("  Disks ({0})           : {1}" -f $disks.Count, (Format-GB $diskBytes))
    Write-Info ("  Snapshots ({0})       : {1}" -f $snapshots.Count, (Format-GB $avhdxBytes))
    Write-Info ("  Total folder         : {0}" -f (Format-GB $folderBytes))
}

if ($vmReports.Count -eq 0) {
    Write-Fatal 'No matching VMs found.'
}

Write-Host ''

# -- Totals -------------------------------------------------------------------
$totalDisks          = ($vmReports.DiskBytes          | Measure-Object -Sum).Sum
$totalSnapshots      = ($vmReports.SnapshotBytes      | Measure-Object -Sum).Sum
$totalFolder         = ($vmReports.FolderBytes        | Measure-Object -Sum).Sum
$totalCleanExport    = ($vmReports.CleanExportEst     | Measure-Object -Sum).Sum
$totalWithCheckpoint = ($vmReports.WithCheckpointsEst | Measure-Object -Sum).Sum

# Headroom: planning rule is total size + 10% buffer for safety
$cleanWithBuffer     = $totalCleanExport    * 1.1
$withCpWithBuffer    = $totalWithCheckpoint * 1.1

Write-Host ('  +-- Per-VM Summary ' + ('-' * 45)) -ForegroundColor DarkCyan
$fmt = '  {0,-22} {1,-10} {2,9} {3,9} {4,9} {5,9}'
Write-Host ($fmt -f 'VM', 'State', 'Disks', 'Snaps', 'Folder', 'CleanExp') -ForegroundColor DarkGray
foreach ($r in $vmReports) {
    $color = if ($r.State -eq 'Running') { 'Green' } elseif ($r.State -eq 'Off') { 'Yellow' } else { 'White' }
    Write-Host ($fmt -f $r.Name,
                        $r.State,
                        (Format-GB $r.DiskBytes).Trim(),
                        (Format-GB $r.SnapshotBytes).Trim(),
                        (Format-GB $r.FolderBytes).Trim(),
                        (Format-GB $r.CleanExportEst).Trim()) -ForegroundColor $color
}
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''

# -- Export Size Estimates ----------------------------------------------------
Write-Host ('  +-- Export Size Estimates ' + ('-' * 38)) -ForegroundColor DarkCyan
Write-Host ("    Clean (no checkpoints) : {0}    Buffered (+10%): {1}" -f (Format-GB $totalCleanExport),    (Format-GB $cleanWithBuffer))  -ForegroundColor Green
Write-Host ("    With checkpoints       : {0}    Buffered (+10%): {1}" -f (Format-GB $totalWithCheckpoint), (Format-GB $withCpWithBuffer)) -ForegroundColor Yellow
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''

# -- Survey target drives -----------------------------------------------------
Write-Host ('  +-- Target Drive Free Space ' + ('-' * 36)) -ForegroundColor DarkCyan

$driveReports = @()
foreach ($letter in $TargetDrives) {
    $clean = $letter.TrimEnd(':')
    $drv = Get-PSDrive -Name $clean -ErrorAction SilentlyContinue
    if (-not $drv) {
        Write-Host ("    [MISSING] {0}: drive not present on this host" -f $clean) -ForegroundColor Red
        $driveReports += [PSCustomObject]@{
            Letter = $clean
            FreeGB = 0
            FitsClean = $false
            FitsWithCheckpoints = $false
        }
        continue
    }

    $freeGB = [math]::Round($drv.Free / 1GB, 1)
    $fitsClean = ($drv.Free -ge $cleanWithBuffer)
    $fitsCP    = ($drv.Free -ge $withCpWithBuffer)

    $color  = if ($fitsClean) { 'Green' } else { 'Red' }
    $marker = if ($fitsClean) { '[OK]    ' } else { '[TIGHT] ' }
    Write-Host ("    $marker {0}: drive  Free = {1,7:N1} GB   Fits clean? {2}   Fits w/ checkpoints? {3}" `
        -f $clean, $freeGB, $(if ($fitsClean) { 'YES' } else { 'NO ' }), $(if ($fitsCP) { 'YES' } else { 'NO ' })) `
        -ForegroundColor $color

    $driveReports += [PSCustomObject]@{
        Letter = $clean
        FreeGB = $freeGB
        FitsClean = $fitsClean
        FitsWithCheckpoints = $fitsCP
    }
}
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''

# -- Recommendation -----------------------------------------------------------
$cleanFitter = $driveReports | Where-Object { $_.FitsClean } | Sort-Object -Property FreeGB -Descending | Select-Object -First 1
if ($cleanFitter) {
    Write-Host ("  Recommendation: export to {0}:\VM-Exports\  (clean mode, {1:N1} GB free, fits with headroom)" `
        -f $cleanFitter.Letter, $cleanFitter.FreeGB) -ForegroundColor Green
    Write-Host ''
    Write-Host '  Run:' -ForegroundColor Cyan
    Write-Host ("    .\Export-LabVMs.ps1 -ExportPath '{0}:\VM-Exports\'" -f $cleanFitter.Letter) -ForegroundColor White
    if ($IncludeWorkstation) {
        Write-Host ("    .\Export-LabVMs.ps1 -ExportPath '{0}:\VM-Exports\' -IncludeWorkstation" -f $cleanFitter.Letter) -ForegroundColor White
    }
} else {
    Write-Host '  Recommendation: NONE of the target drives have enough free space.' -ForegroundColor Red
    Write-Host '  Options:' -ForegroundColor Yellow
    Write-Host '    - Free up space on D:\ (or another drive)' -ForegroundColor Yellow
    Write-Host '    - Use -ExportPath to point at an external USB / NAS drive' -ForegroundColor Yellow
    Write-Host ("    - Need at least {0} of free space" -f (Format-GB $cleanWithBuffer)) -ForegroundColor Yellow
}
Write-Host ''

# -- Optional markdown report -------------------------------------------------
if ($ReportPath) {
    $md = @()
    $md += '# Lab VM Size + Export Planning Report'
    $md += ''
    $md += "**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
    $md += "**Source host:** $env:COMPUTERNAME"
    $md += "**Script:** Get-LabVMSize.ps1"
    $md += ''
    $md += '## Per-VM Summary'
    $md += ''
    $md += '| VM | State | Disks | Snaps | Folder | Clean Export Est |'
    $md += '|---|---|---|---|---|---|'
    foreach ($r in $vmReports) {
        $md += ('| {0} | {1} | {2} | {3} | {4} | {5} |' -f $r.Name, $r.State,
                (Format-GB $r.DiskBytes).Trim(),
                (Format-GB $r.SnapshotBytes).Trim(),
                (Format-GB $r.FolderBytes).Trim(),
                (Format-GB $r.CleanExportEst).Trim())
    }
    $md += ''
    $md += '## Export Size Estimates'
    $md += ''
    $md += ('- **Clean (no checkpoints):** {0}, buffered to {1}' -f (Format-GB $totalCleanExport).Trim(), (Format-GB $cleanWithBuffer).Trim())
    $md += ('- **With checkpoints:**      {0}, buffered to {1}' -f (Format-GB $totalWithCheckpoint).Trim(), (Format-GB $withCpWithBuffer).Trim())
    $md += ''
    $md += '## Target Drive Free Space'
    $md += ''
    $md += '| Drive | Free | Fits clean? | Fits w/ checkpoints? |'
    $md += '|---|---|---|---|'
    foreach ($d in $driveReports) {
        $clean = if ($d.FitsClean) { 'YES' } else { 'NO' }
        $cp    = if ($d.FitsWithCheckpoints) { 'YES' } else { 'NO' }
        $md += ('| {0}: | {1:N1} GB | {2} | {3} |' -f $d.Letter, $d.FreeGB, $clean, $cp)
    }
    $md += ''
    $md += '## Recommendation'
    $md += ''
    if ($cleanFitter) {
        $md += ("Export to ``{0}:\VM-Exports\`` - clean mode, {1:N1} GB free." -f $cleanFitter.Letter, $cleanFitter.FreeGB)
        $md += ''
        $md += '```powershell'
        $md += (".\Export-LabVMs.ps1 -ExportPath '{0}:\VM-Exports\'$(if ($IncludeWorkstation) { ' -IncludeWorkstation' })" -f $cleanFitter.Letter)
        $md += '```'
    } else {
        $md += '**No target drive has enough free space.** Options:'
        $md += ''
        $md += '- Free up space on D:\ (or another drive)'
        $md += '- Use -ExportPath to point at an external USB / NAS drive'
        $md += ("- Need at least {0} of free space" -f (Format-GB $cleanWithBuffer).Trim())
    }
    $md += ''
    $md += '---'
    $md += ''
    $md += '*Generated by `Get-LabVMSize.ps1` - non-destructive planning report.*'

    $md | Out-File -FilePath $ReportPath -Encoding UTF8
    Write-OK "Report written to: $ReportPath"
    Write-Host ''
}

Write-Host '  Done. Run Export-LabVMs.ps1 when ready.' -ForegroundColor Green
Write-Host ''
