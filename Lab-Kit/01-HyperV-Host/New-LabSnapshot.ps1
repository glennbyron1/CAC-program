#Requires -Version 5.1
<#
.SYNOPSIS
    Hyper-V Lab Checkpoint Manager — Create, list, restore, and clean up named snapshots.

.DESCRIPTION
    Manages Hyper-V checkpoints for the CAC/PIV lab VM set (Lab-OfflineRootCA,
    Lab-DC01, Lab-Workstation01). Taking a checkpoint before each major phase
    means you can roll back instantly if something breaks during the SCAP scan,
    CA configuration, or GPO hardening — without rebuilding from scratch.

    Recommended checkpoint schedule:
      00-BaseOS        After OS install and Set-VMPostConfig — clean OS baseline
      01-DomainJoined  After Build-CAC-Lab.ps1 — domain + DNS working
      02-PKI-Ready     After Root CA + Issuing CA configured and CRL publishing live
      03-Before-Scan   Immediately before the SCAP SCC before-hardening scan
      04-After-GPO     After Build-CA-GPO.ps1 + Enforce-SmartCard.ps1 applied
      05-After-Scan    After SCAP SCC after-hardening scan completes
      06-Validated     After Invoke-LabValidation.ps1 passes all checks

    Modes:
      Create   — Snapshot all lab VMs (or a named subset) with a phase label
      List     — Show all checkpoints across lab VMs in a table
      Restore  — Restore all lab VMs to a named checkpoint
      Delete   — Delete a named checkpoint from all lab VMs
      Cleanup  — Keep only the N most recent checkpoints per VM (prune old ones)

.PARAMETER Mode
    Create | List | Restore | Delete | Cleanup

.PARAMETER Label
    Checkpoint label used in Create / Restore / Delete.
    The script prepends a timestamp so multiple "Before-Scan" checkpoints
    can exist — when restoring or deleting, the most recent matching label
    is used unless -Exact is specified.

    Suggested labels: 00-BaseOS, 01-DomainJoined, 02-PKI-Ready,
                      03-Before-Scan, 04-After-GPO, 05-After-Scan, 06-Validated

.PARAMETER VMs
    Which lab VMs to act on. Default: all three lab VMs that exist on this host.
    Pass a subset if you only want to checkpoint the DC, for example.

.PARAMETER Keep
    Used with -Mode Cleanup. Number of checkpoints per VM to retain (newest first).
    Default: 5

.PARAMETER Exact
    When set, Restore and Delete match the checkpoint name exactly instead of
    selecting the most recent checkpoint whose name contains the label.

.EXAMPLE
    # Snapshot all VMs before the SCAP baseline scan
    .\New-LabSnapshot.ps1 -Mode Create -Label "03-Before-Scan"

    # List all checkpoints across all lab VMs
    .\New-LabSnapshot.ps1 -Mode List

    # Roll everything back to the post-GPO state
    .\New-LabSnapshot.ps1 -Mode Restore -Label "04-After-GPO"

    # Checkpoint only the DC
    .\New-LabSnapshot.ps1 -Mode Create -Label "02-PKI-Ready" -VMs "Lab-DC01"

    # Prune old checkpoints, keeping the 5 most recent per VM
    .\New-LabSnapshot.ps1 -Mode Cleanup -Keep 5

.NOTES
    Author  : Glenn Byron
    Run on  : The Hyper-V HOST (not inside a VM). Must run as Administrator.

    CHECKPOINT STORAGE NOTE:
    Checkpoints consume disk space (differencing disks). Before the SCAP scan
    each VM may be 60–80 GB — a single checkpoint set can add 10–20 GB per VM
    as changes accumulate. Run -Mode Cleanup periodically during lab work.

    RUNNING VMs:
    This script checkpoints VMs regardless of power state. Checkpointing a running
    VM uses a "Production Checkpoint" (VSS-based, application-consistent) if the
    VM supports it; otherwise a Standard checkpoint. For the cleanest restore
    points, shut down the VM first — the script warns you if a VM is running.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Create','List','Restore','Delete','Cleanup')]
    [string]$Mode,

    [Parameter()]
    [string]$Label = '',

    [Parameter()]
    [string[]]$VMs = @('Lab-OfflineRootCA','Lab-DC01','Lab-Workstation01'),

    [Parameter()]
    [int]$Keep = 5,

    [Parameter()]
    [switch]$Exact
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
function Write-Banner {
    Write-Host ""
    Write-Host ("=" * 68) -ForegroundColor DarkCyan
    Write-Host "  HYPER-V LAB CHECKPOINT MANAGER  |  Mode: $Mode" -ForegroundColor Cyan
    Write-Host "  Author: Glenn Byron" -ForegroundColor Cyan
    Write-Host ("=" * 68) -ForegroundColor DarkCyan
    Write-Host ""
}

function Write-OK   { param([string]$M) Write-Host "  [OK]    $M" -ForegroundColor Green  }
function Write-Warn { param([string]$M) Write-Host "  [WARN]  $M" -ForegroundColor Yellow }
function Write-Err  { param([string]$M) Write-Host "  [FAIL]  $M" -ForegroundColor Red    }
function Write-Info { param([string]$M) Write-Host "  [INFO]  $M" -ForegroundColor Cyan   }
function Write-Step { param([string]$M) Write-Host ""
                      Write-Host "  ── $M" -ForegroundColor White }

# ---------------------------------------------------------------------------
# Resolve which VMs exist on this host
# ---------------------------------------------------------------------------
function Get-LabVMs {
    param([string[]]$Requested)
    $found = @()
    foreach ($name in $Requested) {
        $vm = Get-VM -Name $name -ErrorAction SilentlyContinue
        if ($vm) {
            $found += $vm
        } else {
            Write-Warn "VM '$name' not found on this host — skipping."
        }
    }
    if ($found.Count -eq 0) {
        throw "No lab VMs found on this host. Check that Hyper-V is running and VM names match."
    }
    return $found
}

# ---------------------------------------------------------------------------
# Create
# ---------------------------------------------------------------------------
function Invoke-Create {
    param([string]$Label, [object[]]$LabVMs)

    if (-not $Label) { throw "-Label is required for Create mode. Example: -Label '03-Before-Scan'" }

    $stamp      = (Get-Date).ToString("yyyyMMdd-HHmm")
    $checkpointName = "$stamp-$Label"

    Write-Step "Creating checkpoint: '$checkpointName'"
    Write-Info "All VMs: $($LabVMs.Name -join ', ')"
    Write-Host ""

    foreach ($vm in $LabVMs) {
        if ($vm.State -eq 'Running') {
            Write-Warn "$($vm.Name) is running. A Production Checkpoint will be attempted (VSS-based)."
            Write-Warn "For cleanest results, shut the VM down first."
        }

        Write-Info "Checkpointing $($vm.Name)..."
        if ($PSCmdlet.ShouldProcess($vm.Name, "Checkpoint-VM '$checkpointName'")) {
            Checkpoint-VM -VM $vm -SnapshotName $checkpointName -ErrorAction Stop
            Write-OK "$($vm.Name) — '$checkpointName'"
        }
    }

    Write-Host ""
    Write-OK "Checkpoint created on $($LabVMs.Count) VM(s)."
    Write-Info "To restore: .\New-LabSnapshot.ps1 -Mode Restore -Label '$Label'"
}

# ---------------------------------------------------------------------------
# List
# ---------------------------------------------------------------------------
function Invoke-List {
    param([object[]]$LabVMs)

    Write-Step "Checkpoints across lab VMs"
    Write-Host ""

    $any = $false
    foreach ($vm in $LabVMs) {
        $snaps = Get-VMSnapshot -VM $vm | Sort-Object CreationTime -Descending
        if (-not $snaps) {
            Write-Info "$($vm.Name) — no checkpoints"
            continue
        }
        $any = $true
        Write-Host "  $($vm.Name)" -ForegroundColor White
        foreach ($s in $snaps) {
            $age  = ((Get-Date) - $s.CreationTime).TotalDays
            $ageS = if ($age -lt 1) { "today" } elseif ($age -lt 2) { "yesterday" } else { "$([math]::Round($age,0)) days ago" }
            $state = $s.ParentSnapshotName ? "  (parent: $($s.ParentSnapshotName))" : ""
            Write-Host ("    {0,-36}  {1,-20}  {2}" -f `
                $s.Name,
                $s.CreationTime.ToString("yyyy-MM-dd HH:mm"),
                $ageS) -ForegroundColor Gray
        }
        Write-Host ""
    }

    if (-not $any) {
        Write-Info "No checkpoints found on any lab VM."
    }
}

# ---------------------------------------------------------------------------
# Restore
# ---------------------------------------------------------------------------
function Invoke-Restore {
    param([string]$Label, [object[]]$LabVMs, [bool]$Exact)

    if (-not $Label) { throw "-Label is required for Restore mode." }

    Write-Step "Restoring to checkpoint matching '$Label'"
    Write-Host ""
    Write-Warn "This will REVERT all VMs to the selected checkpoint."
    Write-Warn "Any changes made after that checkpoint will be lost."
    Write-Host ""
    $confirm = Read-Host "  Type RESTORE to confirm, or anything else to abort"
    if ($confirm -ne 'RESTORE') {
        Write-Info "Restore aborted."
        return
    }
    Write-Host ""

    foreach ($vm in $LabVMs) {
        $snaps = Get-VMSnapshot -VM $vm | Sort-Object CreationTime -Descending

        $target = if ($Exact) {
            $snaps | Where-Object { $_.Name -eq $Label } | Select-Object -First 1
        } else {
            $snaps | Where-Object { $_.Name -like "*$Label*" } | Select-Object -First 1
        }

        if (-not $target) {
            Write-Warn "$($vm.Name) — no checkpoint matching '$Label' found, skipping."
            continue
        }

        Write-Info "Restoring $($vm.Name) to '$($target.Name)'..."
        if ($vm.State -eq 'Running') {
            Write-Info "Stopping $($vm.Name) before restore..."
            if ($PSCmdlet.ShouldProcess($vm.Name, "Stop-VM")) {
                Stop-VM -VM $vm -Force -TurnOff
            }
        }

        if ($PSCmdlet.ShouldProcess($vm.Name, "Restore-VMSnapshot '$($target.Name)'")) {
            Restore-VMSnapshot -VMSnapshot $target -Confirm:$false
            Write-OK "$($vm.Name) restored to '$($target.Name)'"
        }
    }

    Write-Host ""
    Write-OK "Restore complete. Start the VMs when ready."
    Write-Info "Start all VMs: Get-VM Lab-* | Start-VM"
}

# ---------------------------------------------------------------------------
# Delete
# ---------------------------------------------------------------------------
function Invoke-Delete {
    param([string]$Label, [object[]]$LabVMs, [bool]$Exact)

    if (-not $Label) { throw "-Label is required for Delete mode." }

    Write-Step "Deleting checkpoint matching '$Label'"
    Write-Host ""

    foreach ($vm in $LabVMs) {
        $snaps = Get-VMSnapshot -VM $vm | Sort-Object CreationTime -Descending

        $targets = if ($Exact) {
            $snaps | Where-Object { $_.Name -eq $Label }
        } else {
            $snaps | Where-Object { $_.Name -like "*$Label*" }
        }

        if (-not $targets) {
            Write-Info "$($vm.Name) — no checkpoint matching '$Label', skipping."
            continue
        }

        foreach ($t in $targets) {
            Write-Info "Deleting $($vm.Name) / '$($t.Name)'..."
            if ($PSCmdlet.ShouldProcess($vm.Name, "Remove-VMSnapshot '$($t.Name)'")) {
                Remove-VMSnapshot -VMSnapshot $t -IncludeAllChildSnapshots -Confirm:$false
                Write-OK "$($vm.Name) — '$($t.Name)' deleted"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Cleanup — keep newest N checkpoints per VM
# ---------------------------------------------------------------------------
function Invoke-Cleanup {
    param([object[]]$LabVMs, [int]$Keep)

    Write-Step "Pruning old checkpoints (keeping $Keep most recent per VM)"
    Write-Host ""

    foreach ($vm in $LabVMs) {
        $snaps = Get-VMSnapshot -VM $vm | Sort-Object CreationTime -Descending

        if ($snaps.Count -le $Keep) {
            Write-Info "$($vm.Name) — $($snaps.Count) checkpoint(s), nothing to prune."
            continue
        }

        $toDelete = $snaps | Select-Object -Skip $Keep
        Write-Info "$($vm.Name) — removing $($toDelete.Count) old checkpoint(s)..."

        foreach ($s in $toDelete) {
            if ($PSCmdlet.ShouldProcess($vm.Name, "Remove-VMSnapshot '$($s.Name)'")) {
                Remove-VMSnapshot -VMSnapshot $s -IncludeAllChildSnapshots -Confirm:$false
                Write-OK "  Deleted: $($s.Name)"
            }
        }
    }

    Write-Host ""
    Write-OK "Cleanup complete."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
Write-Banner

# Admin check
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "This script must run as Administrator."
}

if (-not (Get-Command Get-VM -ErrorAction SilentlyContinue)) {
    throw "Hyper-V PowerShell module not found. Install the Hyper-V management tools first."
}

$labVMs = Get-LabVMs -Requested $VMs

switch ($Mode) {
    'Create'  { Invoke-Create  -Label $Label -LabVMs $labVMs }
    'List'    { Invoke-List    -LabVMs $labVMs }
    'Restore' { Invoke-Restore -Label $Label -LabVMs $labVMs -Exact $Exact.IsPresent }
    'Delete'  { Invoke-Delete  -Label $Label -LabVMs $labVMs -Exact $Exact.IsPresent }
    'Cleanup' { Invoke-Cleanup -LabVMs $labVMs -Keep $Keep }
}

Write-Host ""
