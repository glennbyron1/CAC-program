#Requires -Version 5.1
<#
.SYNOPSIS
    Exports lab VMs to a portable folder for reuse, backup, or migration to
    a Home-Lab track. Defaults to exporting Lab-DC01 and Lab-OfflineRootCA
    in a clean single-state form (no embedded checkpoints).

.DESCRIPTION
    Wraps Hyper-V's Export-VM with sane defaults for the CAC lab. By default:
      - Exports Lab-DC01 and Lab-OfflineRootCA only (use -IncludeWorkstation to add WS01)
      - Gracefully shuts down running VMs first (clean state, no USN rollback risk)
      - Strips checkpoints before export (use -IncludeCheckpoints to keep them)
      - Writes to D:\VM-Exports\<yyyyMMdd-HHmm>\ by default
      - Verifies the target drive has enough free space first
      - Restarts the VMs after export completes (use -LeaveVMsOff to skip)

    For a Domain Controller export, a clean shutdown is strongly preferred over
    a live/saved-state export to avoid USN rollback issues on restore.

.PARAMETER ExportPath
    Folder to write the export package(s) to. A timestamped subfolder is created
    inside this path. Default: D:\VM-Exports\

.PARAMETER VMNames
    Array of VM names to export. Defaults to Lab-DC01 + Lab-OfflineRootCA.

.PARAMETER IncludeWorkstation
    Switch - also exports Lab-Workstation01. Off by default.

.PARAMETER IncludeCheckpoints
    Switch - preserves snapshot checkpoints inside the export. Off by default
    (clean single-state export is smaller and avoids restore-state ambiguity).

.PARAMETER SkipShutdown
    Switch - do NOT shut down running VMs first. Hyper-V will do a live/saved-state
    export. Risky for domain controllers - use only if you know why.

.PARAMETER LeaveVMsOff
    Switch - leave VMs off after export. Default behavior is to restart any VM
    that was running before the export.

.PARAMETER SkipDriveCheck
    Switch - skip the free-space pre-check on the destination drive.

.EXAMPLE
    # Default - DC01 + OfflineRootCA, clean shutdown, to D:\VM-Exports\<timestamp>\
    .\Export-LabVMs.ps1

.EXAMPLE
    # Include the workstation
    .\Export-LabVMs.ps1 -IncludeWorkstation

.EXAMPLE
    # Custom target, keep checkpoints
    .\Export-LabVMs.ps1 -ExportPath "E:\Backup\Lab\" -IncludeCheckpoints

.EXAMPLE
    # Export-only run (leave VMs off for the user to handle)
    .\Export-LabVMs.ps1 -LeaveVMsOff

.NOTES
    Author     : Glenn Byron
    Project    : CAC-Program
    Last Edit  : 2026-06-02
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ExportPath         = 'D:\VM-Exports\',
    [string[]]$VMNames          = @('Lab-DC01', 'Lab-OfflineRootCA'),
    [switch]$IncludeWorkstation,
    [switch]$IncludeCheckpoints,
    [switch]$SkipShutdown,
    [switch]$LeaveVMsOff,
    [switch]$SkipDriveCheck
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
Write-Host ""
Write-Host "  +======================================================+" -ForegroundColor DarkCyan
Write-Host "  |     CAC Lab Kit - Export Lab VMs to Portable Pkg     |" -ForegroundColor DarkCyan
Write-Host "  +======================================================+" -ForegroundColor DarkCyan
Write-Host ""

# -- Build final VM list ------------------------------------------------------
if ($IncludeWorkstation -and ($VMNames -notcontains 'Lab-Workstation01')) {
    $VMNames += 'Lab-Workstation01'
}

Write-Step "Target export path : $ExportPath"
Write-Step "VMs to export      : $($VMNames -join ', ')"
Write-Step "Include checkpoints: $($IncludeCheckpoints.IsPresent)"
Write-Step "Shutdown first     : $(-not $SkipShutdown.IsPresent)"
Write-Host ""

# -- Validate Hyper-V is available --------------------------------------------
if (-not (Get-Command Export-VM -ErrorAction SilentlyContinue)) {
    Write-Fatal 'Hyper-V PowerShell module not available. Run this on the Hyper-V host as Administrator.'
}

# -- Validate each VM exists --------------------------------------------------
$vms = @()
foreach ($name in $VMNames) {
    $vm = Get-VM -Name $name -ErrorAction SilentlyContinue
    if (-not $vm) {
        Write-Warn "VM not found, skipping: $name"
        continue
    }
    $vms += $vm
}
if ($vms.Count -eq 0) {
    Write-Fatal 'No matching VMs found. Aborting.'
}

# -- Compute on-disk size to estimate export size -----------------------------
Write-Step 'Calculating estimated export size...'
$totalBytes = 0
foreach ($vm in $vms) {
    $vmFolder  = Split-Path $vm.Path -Parent
    $vmSize    = (Get-ChildItem $vmFolder -Recurse -File -ErrorAction SilentlyContinue |
                  Measure-Object Length -Sum).Sum
    $totalBytes += $vmSize
    Write-Info ("  {0,-25} {1,8:N1} GB" -f $vm.Name, ($vmSize / 1GB))
}
$totalGB   = [math]::Round($totalBytes / 1GB, 1)
$neededGB  = [math]::Round($totalGB * 1.1, 1)   # 10% headroom
Write-OK "Total estimated      : $totalGB GB  (need $neededGB GB free with headroom)"
Write-Host ""

# -- Pre-check destination drive free space -----------------------------------
if (-not $SkipDriveCheck) {
    # Ensure root drive exists
    $exportRoot = Split-Path $ExportPath -Qualifier
    $drive = Get-PSDrive -Name ($exportRoot.TrimEnd(':')) -ErrorAction SilentlyContinue
    if (-not $drive) {
        Write-Fatal "Drive $exportRoot not found. Plug in the external drive or fix -ExportPath."
    }
    $freeGB = [math]::Round($drive.Free / 1GB, 1)
    Write-Step "Drive $exportRoot has $freeGB GB free"
    if ($freeGB -lt $neededGB) {
        Write-Fatal "Insufficient free space on $exportRoot. Need $neededGB GB, have $freeGB GB. Use -ExportPath to point elsewhere or free up space."
    }
    Write-OK 'Free-space check passed'
    Write-Host ""
}

# -- Create timestamped target folder -----------------------------------------
$timestamp     = Get-Date -Format 'yyyyMMdd-HHmm'
$exportSubdir  = Join-Path $ExportPath "LabExport-$timestamp"

if ($PSCmdlet.ShouldProcess($exportSubdir, 'Create export folder')) {
    New-Item -ItemType Directory -Path $exportSubdir -Force | Out-Null
    Write-OK "Created: $exportSubdir"
    Write-Host ""
}

# -- Track which VMs we shut down so we can restart them ----------------------
$vmsToRestart = @()

# -- Shutdown phase -----------------------------------------------------------
if (-not $SkipShutdown) {
    Write-Step 'Shutting down running VMs (graceful)...'
    foreach ($vm in $vms) {
        if ($vm.State -eq 'Running') {
            if ($PSCmdlet.ShouldProcess($vm.Name, 'Stop-VM')) {
                Write-Info "  Stopping $($vm.Name)..."
                Stop-VM -Name $vm.Name -Force
                $vmsToRestart += $vm.Name
                Write-OK "$($vm.Name) is now Off"
            }
        } elseif ($vm.State -eq 'Saved') {
            Write-Warn "$($vm.Name) is in SavedState - exporting as-is (consider Start + clean shutdown later)"
        } else {
            Write-Info "  $($vm.Name) already off"
        }
    }
    Write-Host ""
} else {
    Write-Warn 'SkipShutdown set - VMs will be exported in their current state'
    Write-Info 'For domain controllers this risks USN rollback on restore. You have been warned.'
    Write-Host ""
}

# -- Optionally strip checkpoints --------------------------------------------
if (-not $IncludeCheckpoints) {
    Write-Step 'Removing checkpoints for clean single-state export...'
    foreach ($vm in $vms) {
        $cps = Get-VMSnapshot -VMName $vm.Name -ErrorAction SilentlyContinue
        if ($cps -and $cps.Count -gt 0) {
            Write-Info "  $($vm.Name) has $($cps.Count) checkpoint(s) - merging..."
            if ($PSCmdlet.ShouldProcess($vm.Name, 'Remove all checkpoints')) {
                Remove-VMSnapshot -VMName $vm.Name -IncludeAllChildSnapshots -Confirm:$false
                # Wait for merge to settle
                Start-Sleep -Seconds 3
                $remaining = Get-VMSnapshot -VMName $vm.Name -ErrorAction SilentlyContinue
                if ($remaining) {
                    Write-Warn "$($vm.Name) still has checkpoints after merge - export will preserve them"
                } else {
                    Write-OK "$($vm.Name) checkpoints merged"
                }
            }
        } else {
            Write-Info "  $($vm.Name) has no checkpoints"
        }
    }
    Write-Host ""
} else {
    Write-Step 'Keeping checkpoints in export (-IncludeCheckpoints set)'
    Write-Host ''
}

# -- Export each VM -----------------------------------------------------------
Write-Step 'Exporting VMs (this is the slow part - 30-60 min per VM is normal)...'
Write-Host ''

$exportResults = @()
foreach ($vm in $vms) {
    $vmStart = Get-Date
    Write-Step "Exporting: $($vm.Name)"
    if ($PSCmdlet.ShouldProcess($vm.Name, "Export-VM to $exportSubdir")) {
        try {
            Export-VM -Name $vm.Name -Path $exportSubdir -ErrorAction Stop
            $vmDur = (Get-Date) - $vmStart
            $vmExportDir  = Join-Path $exportSubdir $vm.Name
            $exportedSize = if (Test-Path $vmExportDir) {
                (Get-ChildItem $vmExportDir -Recurse -File -ErrorAction SilentlyContinue |
                 Measure-Object Length -Sum).Sum / 1GB
            } else { 0 }
            Write-OK ("$($vm.Name) exported - {0:N1} GB in {1:mm}m{1:ss}s" -f $exportedSize, $vmDur)
            $exportResults += [PSCustomObject]@{
                VM       = $vm.Name
                Status   = 'OK'
                SizeGB   = [math]::Round($exportedSize, 1)
                Duration = $vmDur
            }
        } catch {
            Write-Warn "$($vm.Name) export FAILED: $($_.Exception.Message)"
            $exportResults += [PSCustomObject]@{
                VM       = $vm.Name
                Status   = 'FAILED'
                SizeGB   = 0
                Duration = $null
            }
        }
    }
    Write-Host ''
}

# -- Restart VMs if requested -------------------------------------------------
if ($vmsToRestart.Count -gt 0 -and -not $LeaveVMsOff) {
    Write-Step 'Restarting VMs that were running before export...'
    foreach ($name in $vmsToRestart) {
        if ($PSCmdlet.ShouldProcess($name, 'Start-VM')) {
            try {
                Start-VM -Name $name
                Write-OK "$name started"
            } catch {
                Write-Warn "Failed to start $name : $($_.Exception.Message)"
            }
        }
    }
    Write-Host ''
} elseif ($LeaveVMsOff -and $vmsToRestart.Count -gt 0) {
    Write-Warn "LeaveVMsOff set - $($vmsToRestart.Count) VM(s) remain off. Start manually when ready."
    Write-Host ''
}

# -- Write a manifest into the export folder ----------------------------------
$manifest = @"
# Lab Export Manifest

**Created:** $(Get-Date -Format 'yyyy-MM-dd HH:mm')
**Source host:** $env:COMPUTERNAME
**Created by:** $env:USERNAME
**Script:** Export-LabVMs.ps1

## VMs Exported

$(foreach ($r in $exportResults) {
    "- **$($r.VM)** - $($r.Status) - $($r.SizeGB) GB"
})

## Configuration

- Export path: $exportSubdir
- Checkpoints included: $($IncludeCheckpoints.IsPresent)
- Clean shutdown: $(-not $SkipShutdown.IsPresent)
- VMs restarted after export: $(-not $LeaveVMsOff.IsPresent)

## To Restore

Use Import-LabVM.ps1 (companion script):

``````powershell
.\Import-LabVM.ps1 -ImportPath '$exportSubdir\Lab-DC01' -Copy
``````

Or via Hyper-V Manager: Action -> Import Virtual Machine -> point at the
VM folder under $exportSubdir.

## Warnings

- **Domain SID is preserved** in the exported DC. Do NOT run the exported
  DC alongside the original on the same network - duplicate SIDs will break
  Kerberos. See Home-Lab\00-Foundation\VM-Reuse-Workflow.md for guidance.
- This export does not include the Server 2025 ISO or any external tools.
"@

$manifestPath = Join-Path $exportSubdir 'EXPORT-MANIFEST.md'
$manifest | Out-File -FilePath $manifestPath -Encoding UTF8
Write-Step "Manifest written: $manifestPath"
Write-Host ''

# -- Summary ------------------------------------------------------------------
Write-Host ('  +-- Summary ' + ('-' * 50)) -ForegroundColor DarkCyan
foreach ($r in $exportResults) {
    $marker = if ($r.Status -eq 'OK') { '[OK]     ' } else { '[FAILED] ' }
    $color  = if ($r.Status -eq 'OK') { 'Green'   } else { 'Red'      }
    Write-Host ("    $marker $($r.VM) - $($r.SizeGB) GB") -ForegroundColor $color
}
Write-Host ('  +--' + ('-' * 60)) -ForegroundColor DarkCyan
Write-Host ''
Write-Step "Export location: $exportSubdir"
Write-Host ''
Write-Host '  Done. Import with .\Import-LabVM.ps1 -ImportPath <subfolder> -Copy' -ForegroundColor Green
Write-Host ''
